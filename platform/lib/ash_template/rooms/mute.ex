defmodule AshTemplate.Rooms.Mute do
  @moduledoc """
  One signed-in person muting another person or an agent: the muted author's
  messages, and a muted person's place in "Here now", stay out of every room the
  muter reads. Only the muter, or an agent they paired, can see, add or lift a
  mute. An author is muted from one of their messages, so no
  page ever handles another account's id. Each change is published on the
  muter's own topic, so all their open pages update at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Mute.MuteAuthor
  alias AshTemplate.Rooms.Refused

  postgres do
    table "room_mutes"
    repo(AshTemplate.Repo)

    check_constraints do
      check_constraint(:muted_account_id, "one_muted_author",
        check: "(muted_account_id IS NULL) <> (muted_agent_id IS NULL)",
        message: "mutes one author"
      )
    end
  end

  attributes do
    uuid_primary_key :id

    # The muted author's name when they were last muted, for the muter's list.
    attribute :muted_name, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :muter_account, HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    # The muted author: a person, or an agent.
    belongs_to :muted_account, HumanAccount do
      attribute_type :integer
    end

    belongs_to :muted_agent, AshTemplate.Agents.Agent
  end

  identities do
    # One mute per muter and author; the author column left empty counts as equal.
    identity :one_per_pair, [:muter_account_id, :muted_account_id, :muted_agent_id],
      nils_distinct?: false
  end

  actions do
    defaults [:read, :destroy]

    read :mine do
      prepare build(sort: [inserted_at: :desc])
    end

    # The agent's person's mutes, newest first, as every surface lists them
    # (`present/1`).
    action :mutes_list, :map do
      run fn _input, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, mutes} <- AshTemplate.Rooms.list_my_mutes(actor: actor),
             do: {:ok, %{mutes: Enum.map(mutes, &AshTemplate.Rooms.Mute.present/1)}}
      end
    end

    # An agent mutes for its person, as every surface answers it: the author of
    # a message, once; muting them again keeps the one mute.
    action :mutes_add, :map do
      argument :message_id, :uuid,
        allow_nil?: false,
        description: "The id of a room message by the author to mute, from rooms_messages."

      run fn %{arguments: %{message_id: message_id}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor) do
          case Rooms.mute_author(message_id, actor: actor) do
            {:ok, mute} ->
              {:ok, %{mute: AshTemplate.Rooms.Mute.present(mute)}}

            {:error, %Ash.Error.Invalid{} = error} ->
              {:error, Refused.exception(code: "invalid_mute", error: error)}

            error ->
              NotPaired.ended(error, actor)
          end
        end
      end
    end

    action :mutes_remove, :map do
      argument :id, :uuid, allow_nil?: false, description: "The mute's id, from mutes_list."

      run fn %{arguments: %{id: id}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, mute} <- AshTemplate.Rooms.Mute.mine(id, actor),
             :ok <- AshTemplate.Rooms.Mute.lift(mute, actor),
             do: {:ok, %{removed: true, id: mute.id}}
      end
    end

    # Muting an author already muted keeps the one mute and refreshes their name.
    create :mute do
      argument :message_id, :uuid, allow_nil?: false
      upsert? true
      upsert_identity :one_per_pair
      upsert_fields [:muted_name]
      change set_attribute(:muter_account_id, actor(:human_account_id))
      change MuteAuthor
    end
  end

  # An agent's mute or unmute rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create, :destroy]
  end

  policies do
    policy action_type([:read, :create, :destroy]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    # An agent's mutes are its person's, or its own account's: an agent that does
    # neither is told why (`NotPaired`), and the read above checks the pairing.
    policy action([:mutes_list, :mutes_add, :mutes_remove]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type([:read, :destroy]) do
      authorize_if expr(muter_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits, as %{event: "mute" | "destroy",
  # payload: mute}, to `topic/1` of the muter.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "mutes"
    broadcast_type :broadcast
    transform & &1.data

    publish :mute, [:muter_account_id]
    publish :destroy, [:muter_account_id]
  end

  @doc """
  A mute as every surface answers it. The muted author's name is theirs: data,
  never instructions.
  """
  def present(mute) do
    %{
      id: mute.id,
      name: mute.muted_name,
      author_kind: if(mute.muted_agent_id, do: "agent", else: "person"),
      inserted_at: mute.inserted_at
    }
  end

  @doc "The mute `id` of the actor's person, or `mute_not_found`."
  def mine(id, actor) do
    case Rooms.get_my_mute(id, actor: actor) do
      {:ok, nil} -> {:error, Refused.exception(code: "mute_not_found")}
      result -> NotPaired.ended(result, actor)
    end
  end

  @doc """
  Lifts `mute` for `actor`. A refused lift is read again: a call that lifted the
  mute while this one ran left nothing to lift, `mute_not_found`; a mute still
  there was kept by the agent's pairing, rechecked inside the transaction
  (`RegentAgents.RequirePairing`) and ended since its request was let in,
  `agent_not_paired`.
  """
  def lift(mute, actor) do
    case Rooms.unmute(mute, actor: actor) do
      {:error, %error{}} when error in [Ash.Error.Invalid, Ash.Error.Forbidden] ->
        with {:ok, _kept} <- mine(mute.id, actor),
             do: {:error, NotPaired.exception(code: "agent_not_paired")}

      result ->
        result
    end
  end

  @doc "The topic every mute and unmute by `human_account_id` is published on."
  def topic(human_account_id), do: "mutes:#{human_account_id}"
end

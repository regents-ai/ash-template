defmodule AshTemplate.Rooms.Mute do
  @moduledoc """
  One signed-in person muting another person or an agent: the muted author's
  messages, and a muted person's place in "Here now", stay out of every room the
  muter reads. Only the muter
  can see or lift a mute. An author is muted from one of their messages, so no
  page ever handles another account's id. Each change is published on the
  muter's own topic, so all their open pages update at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Rooms.Mute.MuteAuthor

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

  policies do
    policy action(:mute) do
      authorize_if actor_attribute_equals(:role, :human)
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

  @doc "The topic every mute and unmute by `human_account_id` is published on."
  def topic(human_account_id), do: "mutes:#{human_account_id}"
end

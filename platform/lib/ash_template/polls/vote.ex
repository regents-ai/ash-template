defmodule AshTemplate.Polls.Vote do
  @moduledoc """
  A person's one vote in a poll: the choice they made. An agent they paired
  votes as them, and the vote names it (`via_agent`).

  Sending the same choice again answers the vote already there, and a
  different choice is refused (`CastVote`). Votes are never changed or removed.
  Each person reads only their own; the poll counts everyone's.
  """

  use Ash.Resource,
    domain: AshTemplate.Polls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Polls.Vote.CastVote

  postgres do
    table "poll_votes"
    repo(AshTemplate.Repo)

    references do
      reference(:poll, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :choice, :string, allow_nil?: false, public?: true, constraints: [max_length: 100]
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :poll, AshTemplate.Polls.Poll do
      allow_nil? false
      public? true
    end

    belongs_to :voter, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    # The paired agent that voted for its person; nil when the person did.
    belongs_to :via_agent, AshTemplate.Agents.Agent, public?: true
  end

  identities do
    identity :unique_vote, [:poll_id, :voter_id]
  end

  actions do
    defaults [:read]

    create :cast do
      accept [:choice]
      argument :poll_id, :uuid, allow_nil?: false

      # The person's own vote settles a repeat: the database hands back the
      # vote it already has.
      upsert? true
      upsert_identity :unique_vote
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

      change CastVote
    end
  end

  # An agent's vote rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create]
  end

  policies do
    policy action(:cast) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action(:read) do
      authorize_if actor_attribute_equals(:role, :system)
      authorize_if expr(voter_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits to `AshTemplate.Polls.topic/0`:
  # %{event: "cast", payload: %{poll_id: id}}.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "public"
    broadcast_type :broadcast
    transform &%{poll_id: &1.data.poll_id}

    publish :cast, ["polls"]
  end
end

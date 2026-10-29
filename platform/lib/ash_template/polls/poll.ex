defmodule AshTemplate.Polls.Poll do
  @moduledoc """
  One poll: its question, its choices, who started it and when it closes.

  A signed-in person, or an agent they paired acting for them, starts one, a
  few a day at most (`:poll` in `AshTemplate.Limits`), open for the 1 to 60
  minutes they chose. An agent starts with an `operation_id`, which becomes the
  poll's id, so a retry answers the poll it already started
  (`:started_by_actor`). Only its starter ends it early.

  Anyone reads every poll. Each choice's count is read once the poll has closed
  (`Totals`); until then only how many have voted.
  """

  use Ash.Resource,
    domain: AshTemplate.Polls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Polls.Poll.{DistinctChoices, EndPoll, Starter, Totals}

  @shown [:open, :votes_cast, :totals, :starter, :mine, :my_choice]
  @shown_text "Use letters, numbers and marks you can see."

  postgres do
    table "polls"
    repo(AshTemplate.Repo)

    check_constraints do
      check_constraint(:choices, "polls_choices_count",
        check: "cardinality(choices) BETWEEN 2 AND 10"
      )
    end

    custom_indexes do
      index([:inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :question, :string, allow_nil?: false, public?: true, constraints: [max_length: 200]

    attribute :choices, {:array, :string},
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 2, max_length: 10, items: [max_length: 100]]

    attribute :closes_at, :utc_datetime_usec, allow_nil?: false, public?: true
    # When its starter ended it early; nil when it ran its course.
    attribute :ended_at, :utc_datetime_usec, public?: true
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :started_by, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    # The paired agent that started it for its person; nil when the person did.
    belongs_to :via_agent, AshTemplate.Agents.Agent, public?: true

    has_many :votes, AshTemplate.Polls.Vote
  end

  aggregates do
    count :votes_cast, :votes do
      authorize? false
      public? true
    end

    # Every vote's choice, for the totals once the poll has closed.
    list :vote_choices, :votes, :choice do
      authorize? false
    end
  end

  calculations do
    calculate :open, :boolean, expr(is_nil(ended_at) and closes_at > now()), public?: true
    calculate :totals, {:array, :map}, Totals, public?: true
    # The starter's public name, wallet and picture (`Starter`).
    calculate :starter, :map, Starter, public?: true
    # Whether the reader started it.
    calculate :mine, :boolean, expr(started_by_id == ^actor(:human_account_id)), public?: true

    # The choice the reader voted for; nil until they vote.
    calculate :my_choice,
              :string,
              expr(
                first(votes,
                  field: :choice,
                  query: [filter: voter_id == ^actor(:human_account_id)]
                )
              ),
              public?: true
  end

  actions do
    read :read do
      primary? true
    end

    # The newest hundred, newest first.
    read :list do
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 100, load: @shown)
    end

    read :one do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      prepare build(load: @shown)
    end

    # The poll the actor's person already started with this id, so a retry
    # answers the first start.
    read :started_by_actor do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and started_by_id == ^actor(:human_account_id))
      prepare build(load: @shown)
    end

    create :start do
      accept [:question, :choices]
      argument :minutes, :integer, allow_nil?: false, constraints: [min: 1, max: 60]
      argument :operation_id, :uuid

      change fn changeset, %{actor: actor} ->
        if Map.get(actor || %{}, :role) == :agent and
             is_nil(Ash.Changeset.get_argument(changeset, :operation_id)),
           do:
             Ash.Changeset.add_error(changeset,
               field: :operation_id,
               message: "is required for agent creates"
             ),
           else: changeset
      end

      validate match(:question, RegentFormat.Name.pattern()), message: @shown_text
      validate DistinctChoices

      change set_attribute(:id, arg(:operation_id)), where: [present(:operation_id)]
      change set_attribute(:started_by_id, actor(:human_account_id))
      change set_attribute(:via_agent_id, actor(:acting_agent_id))

      change fn changeset, _context ->
        minutes = Ash.Changeset.get_argument(changeset, :minutes)

        if is_integer(minutes),
          do:
            Ash.Changeset.force_change_attribute(
              changeset,
              :closes_at,
              DateTime.add(DateTime.utc_now(), minutes, :minute)
            ),
          else: changeset
      end

      change {LimitWrites,
              allowance: :poll,
              field: :question,
              message: "You've started as many polls as you can today. Start another tomorrow."}

      change load(@shown)
    end

    update :end do
      accept []
      require_atomic? false
      change EndPoll
      change load(@shown)
    end
  end

  # An agent's start or end rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create, :update]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action(:end) do
      authorize_if expr(started_by_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits to `AshTemplate.Polls.topic/0`:
  # %{event: "start" | "end", payload: %{poll_id: id}}.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "public"
    broadcast_type :broadcast
    transform &%{poll_id: &1.data.id}

    publish :start, ["polls"]
    publish :end, ["polls"]
  end
end

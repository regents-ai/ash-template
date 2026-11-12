defmodule AshTemplate.Polls.Poll do
  @moduledoc """
  One poll: its question, its choices, who started it and when it closes.

  A signed-in person, or an agent they paired acting for them, starts one, a
  few a day at most (`:poll` in `AshTemplate.Limits`), open for the 1 to 60
  minutes they chose. An agent starts with an `operation_id`, which becomes the
  poll's id, so a retry answers the poll it already started
  (`:started_by_actor`). Only its starter ends it early.

  Anyone reads every poll. Each vote is counted on the poll's own row as it is
  saved (`:count_vote`), so reading a poll never counts its votes. Each choice's
  count is read once the poll has closed (`Totals`); until then only how many
  have voted.
  """

  use Ash.Resource,
    domain: AshTemplate.Polls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Query

  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Polls
  alias AshTemplate.Polls.Poll.{Starter, StillOpen, Totals}

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
    # How many have voted, counted by each vote as it is saved (`:count_vote`).
    attribute :votes_cast, :integer, allow_nil?: false, default: 0, public?: true

    # Each choice's votes, `%{choice => votes}`, counted the same way. Only
    # `totals` selects it, and hands it out once the poll has closed.
    attribute :tally, :map, allow_nil?: false, default: %{}, select_by_default?: false
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

  calculations do
    calculate :open, :boolean, expr(is_nil(ended_at) and closes_at > now()), public?: true
    calculate :totals, {:array, :map}, Totals, public?: true
    # Who started it: `%{name, wallet, ens_name, squares, picture}` (Poll.Starter).
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

    # The newest hundred, newest first, as stored; a caller loads what it shows.
    read :list do
      prepare build(sort: [inserted_at: :desc, id: :desc], limit: 100)
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

      change AshTemplate.Agents.RequireOperationId

      validate match(:question, RegentFormat.Name.pattern()), message: @shown_text

      # Each choice is text you can see, and no two are the same, so a vote names
      # exactly one.
      validate fn changeset, _context ->
        choices = Ash.Changeset.get_attribute(changeset, :choices) || []

        cond do
          not Enum.all?(choices, &Regex.match?(RegentFormat.Name.pattern(), &1)) ->
            {:error, field: :choices, message: @shown_text}

          length(Enum.uniq(choices)) != length(choices) ->
            {:error, field: :choices, message: "Give each choice different words."}

          true ->
            :ok
        end
      end

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
      # An agent's start rechecks its pairing inside the transaction.
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
    end

    update :end do
      accept []
      require_atomic? false

      # Only a poll still open ends. It is read again under a lock first: it may
      # have closed or been ended since, and a vote being counted at that moment
      # finishes before it ends (`AshTemplate.Polls.Vote.CastVote`). Ending it
      # was authorized; this only reads it again.
      change before_action(fn %{data: poll} = changeset, _context ->
               current =
                 __MODULE__
                 |> Ash.Query.filter(id == ^poll.id)
                 |> Ash.Query.lock(:for_update)
                 |> Ash.read_one!(authorize?: false)

               if Polls.open?(current) do
                 Ash.Changeset.force_change_attribute(changeset, :ended_at, DateTime.utc_now())
               else
                 Ash.Changeset.add_error(changeset,
                   field: :ended_at,
                   message: "This poll has closed."
                 )
               end
             end)

      change load(@shown)
      # An agent's end rechecks its pairing inside the transaction.
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
    end

    # One vote counted, inside the vote's own transaction and only once the vote
    # is saved (`AshTemplate.Polls.Vote.CastVote`). The update checks the poll is
    # still open, so a vote racing the poll's close or its end is either counted
    # before it or turned away with the whole vote.
    update :count_vote do
      accept []
      argument :choice, :string, allow_nil?: false

      validate StillOpen

      change atomic_update(:votes_cast, expr(votes_cast + 1))

      # The map type takes no expression, so the SQL hands back the stored shape
      # itself (`{:atomic, ...}`): the same map with one more vote for the choice.
      change atomic_update(
               :tally,
               {:atomic,
                expr(
                  fragment(
                    "jsonb_set(?, ARRAY[?::text], to_jsonb(COALESCE((? ->> ?::text)::integer, 0) + 1))",
                    tally,
                    ^arg(:choice),
                    tally,
                    ^arg(:choice)
                  )
                )}
             )
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([:start, :end]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action(:end) do
      authorize_if expr(started_by_id == ^actor(:human_account_id))
    end

    # Reached only from a vote, after the vote itself was allowed.
    policy action(:count_vote) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  # Delivered after the transaction commits. A start or an end goes to
  # `AshTemplate.Polls.topic/0` with the poll's `summary/1`; a vote counted goes
  # to that poll's own `AshTemplate.Polls.topic/1` with how many have voted, and
  # never which way.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "public"
    broadcast_type :broadcast

    publish :start, ["polls"], transform: &__MODULE__.summary(&1.data)
    publish :end, ["polls"], transform: &__MODULE__.summary(&1.data)

    publish :count_vote, ["poll", :id],
      event: "vote",
      transform: &%{id: &1.data.id, votes_cast: &1.data.votes_cast}
  end

  @doc "What the polls list shows of a poll, and what its start and end publish."
  def summary(poll), do: Map.take(poll, [:id, :question, :closes_at, :ended_at, :votes_cast])
end

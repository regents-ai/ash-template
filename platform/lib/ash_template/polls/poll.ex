defmodule AshTemplate.Polls.Poll do
  @moduledoc """
  One poll: its question, its choices, who started it and when it closes.

  A signed-in person, or an agent they paired acting for them, starts one, a
  few a day at most (`:poll` in `AshTemplate.Limits`), open for the 1 to 60
  minutes they chose. An agent starts with an `operation_id`, spent once, which
  becomes the poll's id (`AgentStart`). Only its starter ends it early.

  Anyone reads every poll. Each choice's count is read once the poll has closed
  (`Totals`); until then only how many have voted.

  The polls tools an agent calls (`polls_list`, `polls_show`, `polls_start`,
  `polls_end`, and `AshTemplate.Polls.Vote`'s `polls_vote`) answer the same on
  every surface: its HTTP route, its browser tool and the hosted MCP server.
  """

  use Ash.Resource,
    domain: AshTemplate.Polls,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Polls
  alias AshTemplate.Polls.Poll.{AgentStart, DistinctChoices, EndPoll, Starter, Totals}
  alias AshTemplate.Polls.Refused

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
    # The starter's public name and picture: `%{name, squares, picture}`.
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

    create :start do
      accept [:question, :choices]
      argument :minutes, :integer, allow_nil?: false, constraints: [min: 1, max: 60]

      validate match(:question, RegentFormat.Name.pattern()), message: @shown_text
      validate DistinctChoices

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

    # The newest polls as every surface lists them (`present/1`).
    action :polls_list, :map do
      run fn _input, _context ->
        with {:ok, polls} <- AshTemplate.Polls.list_polls(),
             do: {:ok, %{polls: Enum.map(polls, &AshTemplate.Polls.Poll.present/1)}}
      end
    end

    action :polls_show, :map do
      argument :poll, :uuid, allow_nil?: false, description: "The poll's id, from polls_list."

      run fn %{arguments: %{poll: id}}, _context ->
        with {:ok, poll} <- AshTemplate.Polls.Poll.found(id, nil),
             do: {:ok, %{poll: AshTemplate.Polls.Poll.present(poll)}}
      end
    end

    # A poll an agent starts for its person (`AgentStart`).
    action :polls_start, :map do
      argument :question, :string,
        allow_nil?: false,
        constraints: [max_length: 200],
        description: "The question, 1 to 200 characters."

      argument :choices, {:array, :string},
        allow_nil?: false,
        constraints: [min_length: 2, max_length: 10, items: [max_length: 100]],
        description: "2 to 10 different choices, 1 to 100 characters each."

      argument :minutes, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 60],
        description: "How many minutes it stays open, 1 to 60."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this poll. Keep it when retrying; it becomes the poll's id."

      run AgentStart
    end

    action :polls_end, :map do
      argument :poll, :uuid, allow_nil?: false, description: "The poll's id, from polls_list."

      run fn %{arguments: %{poll: id}}, %{actor: actor} ->
        AshTemplate.Polls.Poll.end_mine(id, actor)
      end
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

    # Anyone reads the polls, except an app connected to a person's account: its
    # token is for its identity tools alone (`AshTemplate.Agents.Connection`).
    policy action([:polls_list, :polls_show]) do
      forbid_if actor_attribute_equals(:role, :connected_app)
      authorize_if always()
    end

    # The poll's own create and end then decide, as for a person.
    policy action([:polls_start, :polls_end]) do
      authorize_if AshTemplate.Agents.AnAgent
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

  @doc "A poll as every surface shows it."
  def present(%__MODULE__{} = poll) do
    %{
      id: poll.id,
      question: poll.question,
      choices: poll.choices,
      open: poll.open,
      closes_at: poll.closes_at,
      ended_at: poll.ended_at,
      votes_cast: poll.votes_cast,
      counts: poll.totals,
      started_by: %{name: poll.starter.name, picture: poll.starter.picture},
      via_agent_id: poll.via_agent_id,
      started_at: poll.inserted_at
    }
  end

  @doc """
  The poll `id`, read as `actor` (who sees their own vote), or `poll_not_found`.
  """
  def found(id, actor) do
    case Polls.get_poll(id, actor: actor) do
      {:ok, nil} -> {:error, Refused.exception(code: "poll_not_found")}
      result -> result
    end
  end

  @doc """
  Ends the poll `id` the actor's person started: `not_poll_starter` for anyone
  else's, `poll_closed` once it has closed or been ended. The poll is the
  person's, so a refused end is otherwise the agent's pairing, ended since its
  request was let in: `agent_not_paired`.
  """
  def end_mine(id, actor) do
    with :ok <- NotPaired.check(actor),
         {:ok, poll} <- found(id, actor) do
      if poll.mine,
        do: end_started(poll, actor),
        else: {:error, Refused.exception(code: "not_poll_starter")}
    end
  end

  defp end_started(poll, actor) do
    case Polls.end_poll(poll, actor: actor) do
      {:ok, poll} ->
        {:ok, %{poll: present(poll)}}

      {:error, %Ash.Error.Invalid{errors: errors}} ->
        if Enum.any?(errors, &match?(%{field: :ended_at}, &1)),
          do: {:error, Refused.exception(code: "poll_closed")},
          else: {:error, NotPaired.exception(code: "agent_not_paired")}

      error ->
        NotPaired.ended(error, actor)
    end
  end
end

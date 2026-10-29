defmodule AshTemplate.Notes.Decision do
  @moduledoc """
  One question Jev was asked about one save of a note: which label fits it.

  Saving a note creates a pending decision in the same transaction, on the
  notes' `:note_saved` signal (`RequestLabel`), and an AshOban trigger then asks Jev
  outside any transaction (`AskJev`). The row records what Jev chose, the model
  that answered, the tokens and what OpenRouter charged. A request that does
  not get through retries with backoff, then records its failure. The writer
  can say once whether the label fits; an agent acting for them says it with
  `notes_rate_label`, the same on every surface.

  Every decision counts against the site's daily number of questions and the
  writer's share of it, checked by the create policy (`UnderDailyBudget`). Only
  the note's writer reads its decisions; each change is published on the
  writer's notes topic.
  """

  use Ash.Resource,
    domain: AshTemplate.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias AshTemplate.Notes.Decision.{
    AskJev,
    RateOnce,
    RecordFailure,
    RequestLabel,
    UnderDailyBudget
  }

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Notes
  alias AshTemplate.Notes.{Labels, Refused}

  postgres do
    table "note_decisions"
    repo(AshTemplate.Repo)

    references do
      reference(:note, on_delete: :delete)
    end

    custom_indexes do
      # The daily budgets count today's rows, the site's and each person's; a
      # note shows its latest decision.
      index([:inserted_at])
      index([:human_account_id, :inserted_at])
      index([:note_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :pairing_id, :uuid
    attribute :question, :string, allow_nil?: false, public?: true
    attribute :choices, {:array, :string}, allow_nil?: false, public?: true

    attribute :state, :atom,
      allow_nil?: false,
      default: :pending,
      public?: true,
      constraints: [one_of: [:pending, :answered, :failed]]

    attribute :choice, :string, public?: true
    attribute :confidence, :float, public?: true
    attribute :model, :string, public?: true
    attribute :input_tokens, :integer, public?: true
    attribute :output_tokens, :integer, public?: true
    attribute :cost_usd, :decimal, public?: true
    attribute :failure, :string, public?: true

    attribute :report, :atom, public?: true, constraints: [one_of: [:fits, :does_not_fit]]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :note, AshTemplate.Notes.Note, allow_nil?: false

    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  signals_in do
    from AshTemplate.Notes.Signals do
      on :note_saved, :request_label
    end
  end

  actions do
    defaults [:read]

    action :request_label do
      argument :signal, AshTemplate.Notes.Signals.NoteSaved, allow_nil?: false
      run fn input, context -> RequestLabel.ask(input.arguments.signal, context) end
    end

    create :ask do
      accept [:note_id]
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      change set_attribute(:pairing_id, actor(:pairing_id))
      change set_attribute(:human_account_id, actor(:human_account_id))
      change set_attribute(:question, Labels.instructions())
      change set_attribute(:choices, Labels.keys())
      change run_oban_trigger(:ask_jev)
    end

    update :ask_jev do
      transaction? false
      require_atomic? false
      change AskJev
    end

    update :failed do
      argument :error, :term
      change RecordFailure
    end

    update :report do
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      accept [:report]
      validate present(:report)
      validate RateOnce, always_atomic?: true
    end

    action :notes_rate_label, :map do
      argument :id, :uuid,
        allow_nil?: false,
        description: "The label's id: label.id on the note, not the note's id."

      argument :report, :atom,
        allow_nil?: false,
        constraints: [one_of: [:fits, :does_not_fit]],
        description: "fits or does_not_fit."

      run fn %{arguments: %{id: id, report: report}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, decision} when not is_nil(decision) <-
               Notes.get_label_decision(id, actor: actor),
             {:ok, decision} <-
               NotPaired.ended(Notes.rate_label(decision, report, actor: actor), actor) do
          {:ok, %{label: %{id: decision.id, rating: decision.report}}}
        else
          {:ok, nil} ->
            {:error, Refused.exception(code: "label_not_found")}

          {:error, %Ash.Error.Invalid{}} ->
            {:error, Refused.exception(code: "invalid_label_report")}

          error ->
            error
        end
      end
    end
  end

  oban do
    triggers do
      trigger :ask_jev do
        action :ask_jev
        where expr(state == :pending)
        queue :outside_calls
        max_attempts 3
        on_error :failed
        on_error_fails_job? true
        # A job that gives up logs one safe line (UnexpectedFailure), not raw text.
        log_errors? false
        log_final_error? false
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Notes.Decision.Workers.AskJev
      end
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy action([:request_label, :ask]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action(:ask) do
      authorize_if UnderDailyBudget
    end

    policy action(:report) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action(:notes_rate_label) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type([:read, :update]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the change commits, as %{event: "ask" | "ask_jev" | "failed"
  # | "report", payload: decision}, to the writer's notes topic.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "notes"
    broadcast_type :broadcast
    transform & &1.data

    publish_all :create, [:human_account_id]
    publish_all :update, [:human_account_id]
  end
end

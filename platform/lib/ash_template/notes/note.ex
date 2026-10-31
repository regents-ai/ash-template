defmodule AshTemplate.Notes.Note do
  @moduledoc """
  A note one signed-in person wrote. Only its writer, or an agent they paired
  acting as them, can read, change or delete it; the agent that made the latest
  save is kept with the note (`changed_by_agent`). Every change is published on the writer's own topic, so each of their
  open pages shows it at once.

  When the site owner has set an address for saved notes, each save also
  queues one job, in the same transaction, that posts the save there
  (`AshTemplate.Notes.Webhook`). A save that rolls back queues nothing. The job
  retries with backoff and records its last failure on the note.

  When the server can ask Jev, each save is told as `:note_saved`
  (`AshTemplate.Notes.Signals`), and a question asks which label fits the note
  (`AshTemplate.Notes.Decision`); `label_decision` is the latest one.

  A pinned note comes first among its writer's notes. An agent pinning one
  costs that person one Regent Credit (`Pin`); unpinning is free.

  An archived note goes after all the others and keeps everything else,
  its pin included; archiving and unarchiving are free.

  Each new note is told as `:note_created`, and one an agent wrote for its
  person is offered to Regent Points (`AshTemplate.Points.Award`). Once its
  transaction has committed it is told again as `:note_committed`, and the visit
  log writes its value step (`AshTemplate.Journey.Value`).
  """

  use Ash.Resource,
    domain: AshTemplate.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias AshTemplate.Notes.Note.{
    AskingJev,
    DeliverWebhook,
    Pin,
    RecordWebhook,
    WebhookAddressSet
  }

  postgres do
    table "notes"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:human_account_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 120]
    attribute :body, :string, public?: true, constraints: [max_length: 10_000]
    timestamps(public?: true)
    attribute :changed_by_pairing_id, :uuid
    attribute :created_by_pairing_id, :uuid

    # Counts saves, so each one's job can tell whether the note was saved again since.
    attribute :revision, :integer, allow_nil?: false, default: 1

    # How the latest save's post to the site owner's address went; nil while no
    # address is set.
    attribute :webhook_state, :atom, constraints: [one_of: [:pending, :sent, :failed]]

    # When the note was pinned to the top of its writer's notes; nil when it is not.
    attribute :pinned_at, :utc_datetime_usec, public?: true

    # When the note was archived, after its writer's other notes; nil when it is not.
    attribute :archived_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end

    # The paired agent that made the latest save, as the writer; nil when they did.
    belongs_to :changed_by_agent, AshTemplate.Agents.Agent, public?: true

    has_one :label_decision, AshTemplate.Notes.Decision do
      public? true
      from_many? true
      sort inserted_at: :desc
    end
  end

  actions do
    defaults [:read]

    destroy :destroy do
      primary? true
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
    end

    read :mine do
      prepare build(
                sort: [
                  archived_at: :desc_nils_first,
                  pinned_at: :desc_nils_last,
                  inserted_at: :desc
                ]
              )
    end

    # The person's notes whose title or text holds `text`, in any case.
    read :search do
      argument :text, :string, allow_nil?: false, constraints: [min_length: 2, max_length: 100]

      filter expr(
               contains(string_downcase(title), string_downcase(^arg(:text))) or
                 contains(string_downcase(body), string_downcase(^arg(:text)))
             )

      prepare build(sort: [inserted_at: :desc], limit: 5)
    end

    create :create do
      primary? true
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      accept [:title, :body]
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

      change set_attribute(:id, arg(:operation_id)), where: [present(:operation_id)]
      change {AshTemplate.Limits.LimitWrites, allowance: :note, field: :body}
      change set_attribute(:human_account_id, actor(:human_account_id))
      change set_attribute(:changed_by_agent_id, actor(:acting_agent_id))
      change set_attribute(:changed_by_pairing_id, actor(:pairing_id))
      change set_attribute(:created_by_pairing_id, actor(:pairing_id))
      change set_attribute(:webhook_state, :pending), where: [WebhookAddressSet]
      change run_oban_trigger(:send_webhook), where: [WebhookAddressSet]
      emit AshTemplate.Notes.Signals, :note_saved, fields: [note_id: :id], where: [AskingJev]
      emit AshTemplate.Notes.Signals, :note_created, fields: [note_id: :id]

      emit AshTemplate.Notes.Signals, :note_committed,
        fields: [note_id: :id],
        phase: :after_transaction
    end

    # The save allowance is counted before the statement, so an edit is not a
    # single atomic statement.
    update :update do
      primary? true
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      accept [:title, :body]
      require_atomic? false
      change {AshTemplate.Limits.LimitWrites, allowance: :note, field: :body}
      change atomic_update(:revision, expr(revision + 1))
      change set_attribute(:changed_by_agent_id, actor(:acting_agent_id))
      change set_attribute(:changed_by_pairing_id, actor(:pairing_id))
      change set_attribute(:webhook_state, :pending), where: [WebhookAddressSet]
      change run_oban_trigger(:send_webhook), where: [WebhookAddressSet]
      emit AshTemplate.Notes.Signals, :note_saved, fields: [note_id: :id], where: [AskingJev]
    end

    update :pin do
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      argument :operation_id, :uuid, allow_nil?: false
      change get_and_lock_for_update()
      change Pin
    end

    update :unpin do
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      change set_attribute(:pinned_at, nil)
    end

    update :archive do
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end

    update :unarchive do
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}
      change set_attribute(:archived_at, nil)
    end

    update :send_webhook do
      transaction? false
      require_atomic? false
      change DeliverWebhook
      change {RecordWebhook, state: :sent}
    end

    update :webhook_failed do
      change {RecordWebhook, state: :failed}
    end
  end

  oban do
    triggers do
      # Every save queues its own job, so there is no sweep to find missed ones.
      # A job whose note has since been sent, failed or deleted ends unrun.
      trigger :send_webhook do
        action :send_webhook
        where expr(webhook_state == :pending)

        extra_args &%{revision: &1.revision, pairing_id: &1.changed_by_pairing_id}

        queue :outside_calls
        max_attempts 5
        on_error :webhook_failed
        on_error_fails_job? true
        # A job that gives up logs one safe line (RegentHttp.UnexpectedFailure), not raw text.
        log_errors? false
        log_final_error? false
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Notes.Note.Workers.SendWebhook
      end
    end
  end

  policies do
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end
  end

  # Delivered after the transaction commits, as %{event: "create" | "update" |
  # "destroy", payload: note}, to `topic/1` of the note's writer. A webhook job
  # recording its outcome changes nothing the writer sees, so it is not published.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "notes"
    broadcast_type :broadcast
    transform & &1.data

    publish_all :create, [:human_account_id]
    publish :update, [:human_account_id]
    publish :pin, [:human_account_id]
    publish :unpin, [:human_account_id]
    publish :archive, [:human_account_id]
    publish :unarchive, [:human_account_id]
    publish_all :destroy, [:human_account_id]
  end

  @doc "The save a webhook job was queued for, from the job running `changeset`."
  def job_revision(%{context: %{ash_oban: %{job: %{args: %{"revision" => revision}}}}}),
    do: revision

  @doc "The topic every change to `human_account_id`'s notes is published on."
  def topic(human_account_id), do: "notes:#{human_account_id}"
end

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

  When the server can ask Jev, each save also asks which label fits the note
  (`AshTemplate.Notes.Decision`); `label_decision` is the latest one.

  A note an agent writes for its person is offered to Regent Points
  (`AgentNotePoints`).
  """

  use Ash.Resource,
    domain: AshTemplate.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias AshTemplate.Notes.Note.{
    AgentNotePoints,
    AskForLabel,
    AskingJev,
    DeliverWebhook,
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

    # Counts saves, so each one's job can tell whether the note was saved again since.
    attribute :revision, :integer, allow_nil?: false, default: 1

    # How the latest save's post to the site owner's address went; nil while no
    # address is set.
    attribute :webhook_state, :atom, constraints: [one_of: [:pending, :sent, :failed]]
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
    defaults [:read, :destroy]

    read :mine do
      prepare build(sort: [inserted_at: :desc])
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
      accept [:title, :body]
      change {AshTemplate.Limits.LimitWrites, allowance: :note, field: :body}
      change set_attribute(:human_account_id, actor(:human_account_id))
      change set_attribute(:changed_by_agent_id, actor(:acting_agent_id))
      change set_attribute(:webhook_state, :pending), where: [WebhookAddressSet]
      change run_oban_trigger(:send_webhook), where: [WebhookAddressSet]
      change AskForLabel, where: [AskingJev]
      change AgentNotePoints, where: [present(:changed_by_agent_id)]
    end

    # The save allowance is counted before the statement, so an edit is not a
    # single atomic statement.
    update :update do
      primary? true
      accept [:title, :body]
      require_atomic? false
      change {AshTemplate.Limits.LimitWrites, allowance: :note, field: :body}
      change atomic_update(:revision, expr(revision + 1))
      change set_attribute(:changed_by_agent_id, actor(:acting_agent_id))
      change set_attribute(:webhook_state, :pending), where: [WebhookAddressSet]
      change run_oban_trigger(:send_webhook), where: [WebhookAddressSet]
      change AskForLabel, where: [AskingJev]
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
        extra_args &%{revision: &1.revision}
        queue :outside_calls
        max_attempts 5
        on_error :webhook_failed
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
    publish_all :destroy, [:human_account_id]
  end

  @doc "The save a webhook job was queued for, from the job running `changeset`."
  def job_revision(%{context: %{ash_oban: %{job: %{args: %{"revision" => revision}}}}}),
    do: revision

  @doc "The topic every change to `human_account_id`'s notes is published on."
  def topic(human_account_id), do: "notes:#{human_account_id}"
end

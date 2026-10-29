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

  A pinned note comes first among its writer's notes. An agent pins one by
  paying 1 USDC or 1 of its person's Credits (`AshTemplate.Payments.NotePin`).
  Unpinning is free.

  An archived note goes after all the others and keeps everything else,
  its pin included; archiving and unarchiving are free.

  Each new note is told as `:note_created`, and one an agent wrote for its
  person is offered to Regent Points (`AshTemplate.Points.Award`).

  What the notes API, the browser tools, regents-cli and the hosted MCP server
  do with notes is one action each, named after its tool (`notes_list` and the
  rest), answering what every surface answers; an agent's new note spends its
  operation key once (`AgentCreate`).
  """

  use Ash.Resource,
    domain: AshTemplate.Notes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias AshTemplate.Actors.Human
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Notes
  alias AshTemplate.Notes.Refused
  alias AshTemplate.Payments.NotePin
  alias RegentPayments.USDC

  alias AshTemplate.Notes.Note.{
    AgentCreate,
    AskingJev,
    DeliverWebhook,
    Pin,
    RecordWebhook,
    SendsAChange,
    WebhookAddressSet
  }

  @note_id "The note's id, from notes_list or notes_search."

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
      change {AshTemplate.Limits.LimitWrites, allowance: :note, field: :body}
      change set_attribute(:human_account_id, actor(:human_account_id))
      change set_attribute(:changed_by_agent_id, actor(:acting_agent_id))
      change set_attribute(:changed_by_pairing_id, actor(:pairing_id))
      change set_attribute(:created_by_pairing_id, actor(:pairing_id))
      change set_attribute(:webhook_state, :pending), where: [WebhookAddressSet]
      change run_oban_trigger(:send_webhook), where: [WebhookAddressSet]
      emit AshTemplate.Notes.Signals, :note_saved, fields: [note_id: :id], where: [AskingJev]
      emit AshTemplate.Notes.Signals, :note_created, fields: [note_id: :id]
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

    # Run by `AshTemplate.Payments.NotePin` once an agent's pin is paid for.
    update :pin do
      require_atomic? false
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

    # The person's notes, newest first after the pinned ones, for them or an agent
    # acting for them.
    action :notes_list, :map do
      run fn _input, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, notes} <- Notes.list_my_notes(actor: actor),
             do: {:ok, %{notes: Enum.map(notes, &AshTemplate.Notes.Note.present/1)}}
      end
    end

    action :notes_get, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      run fn %{arguments: %{id: id}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, note} <- AshTemplate.Notes.Note.mine(id, actor),
             do: {:ok, %{note: AshTemplate.Notes.Note.present(note)}}
      end
    end

    # Up to 5 of the person's notes whose title or text holds `text`.
    action :notes_search, :map do
      argument :text, :string,
        allow_nil?: false,
        constraints: [min_length: 2, max_length: 100],
        description: "Words to look for, 2 to 100 characters, in any case."

      run fn %{arguments: %{text: text}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, notes} <-
               Notes.search_my_notes(text,
                 actor: actor,
                 load: [:label_decision, :changed_by_agent]
               ),
             do: {:ok, %{notes: Enum.map(notes, &AshTemplate.Notes.Note.present/1)}}
      end
    end

    # An agent's new note, its operation_id spent once (`AgentCreate`).
    action :notes_create, :map do
      argument :title, :string,
        allow_nil?: false,
        constraints: [max_length: 120],
        description: "The title, 1 to 120 characters."

      argument :body, :string,
        constraints: [max_length: 10_000],
        description: "The text, up to 10,000 characters."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this note; it becomes the note's id. Keep it when retrying: a retry answers the first note, and a UUID already used for another note is refused."

      run AgentCreate
    end

    # Only the title or text sent is changed (`SendsAChange`).
    action :notes_edit, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      argument :title, :string,
        constraints: [max_length: 120],
        description: "The title, 1 to 120 characters."

      argument :body, :string,
        constraints: [max_length: 10_000],
        description: "The text, up to 10,000 characters."

      validate SendsAChange

      run fn %{arguments: arguments}, %{actor: actor} ->
        AshTemplate.Notes.Note.change_mine(
          arguments.id,
          actor,
          &Notes.update_note(&1, Map.take(arguments, [:title, :body]), actor: actor)
        )
      end
    end

    action :notes_delete, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      run fn %{arguments: %{id: id}}, %{actor: actor} ->
        with :ok <- NotPaired.check(actor),
             {:ok, note} <- AshTemplate.Notes.Note.mine(id, actor),
             :ok <- NotPaired.ended(Notes.destroy_note(note, actor: actor), actor),
             do: {:ok, %{deleted: true, id: note.id}}
      end
    end

    # What pinning the note would cost in USDC or its person's Credits, changing
    # nothing: a pinned note stays as it is and costs nothing (`NotePin`). An
    # agent that owns its account has no pins yet.
    action :notes_pin_price, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      run fn
        _input, %{actor: %Human{}} ->
          {:error, Refused.exception(code: "owner_pins_not_open")}

        %{arguments: %{id: id}}, %{actor: actor} ->
          with :ok <- NotPaired.check(actor),
               {:ok, note} <- AshTemplate.Notes.Note.mine(id, actor) do
            price = USDC.format(if note.pinned_at, do: 0, else: NotePin.price_atomic())

            {:ok,
             %{
               note: %{id: note.id, pinned: !!note.pinned_at},
               price: %{usdc: price, credits: price}
             }}
          end
      end
    end

    action :notes_unpin, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      run fn %{arguments: %{id: id}}, %{actor: actor} ->
        AshTemplate.Notes.Note.change_mine(id, actor, &Notes.unpin_note(&1, actor: actor))
      end
    end

    action :notes_archive, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      run fn %{arguments: %{id: id}}, %{actor: actor} ->
        AshTemplate.Notes.Note.change_mine(id, actor, &Notes.archive_note(&1, actor: actor))
      end
    end

    action :notes_unarchive, :map do
      argument :id, :uuid, allow_nil?: false, description: @note_id

      run fn %{arguments: %{id: id}}, %{actor: actor} ->
        AshTemplate.Notes.Note.change_mine(id, actor, &Notes.unarchive_note(&1, actor: actor))
      end
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
        # A job that gives up logs one safe line (UnexpectedFailure), not raw text.
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

    # The notes a tool reads and changes are checked by the actions it calls.
    policy action([:notes_list, :notes_get, :notes_edit, :notes_delete]) do
      authorize_if AshTemplate.Agents.AnAgent
    end

    policy action([
             :notes_search,
             :notes_create,
             :notes_pin_price,
             :notes_unpin,
             :notes_archive,
             :notes_unarchive
           ]) do
      authorize_if AshTemplate.Agents.AnAgent
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

    # Only a settled payment pins, and its offer checks the payment
    # (`AshTemplate.Payments.NotePin.carry_out/4`) before running it unauthorized.
    policy action(:pin) do
      forbid_if always()
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

  @doc """
  A note as every surface answers it: its fields (`pinned_at` and `archived_at`
  are nil unless it is pinned or archived), its latest `label`, or nil when none
  was asked for, and `changed_by_agent`, or nil when its writer made the latest
  save. `label_decision` and `changed_by_agent` must be loaded.
  """
  @spec present(t()) :: map()
  def present(note) do
    note
    |> Map.take([:id, :title, :body, :pinned_at, :archived_at, :inserted_at, :updated_at])
    |> Map.put(:label, label(note.label_decision))
    |> Map.put(:changed_by_agent, agent(note.changed_by_agent))
  end

  defp agent(nil), do: nil
  defp agent(agent), do: %{id: agent.id, wallet_address: agent.wallet_address}

  defp label(nil), do: nil

  defp label(decision) do
    %{
      id: decision.id,
      state: decision.state,
      choice: decision.choice,
      confidence: decision.confidence,
      rating: decision.report
    }
  end

  @doc """
  The note `id` of the actor's person, or `note_not_found`: another person's note
  reads as absent, exactly like an id that names none.
  """
  def mine(id, actor) do
    case Notes.get_my_note(id, actor: actor) do
      {:ok, nil} -> {:error, Refused.exception(code: "note_not_found")}
      result -> result
    end
  end

  @doc """
  `change` made to the note `id` of the actor's person, answered with the note;
  a save the note refuses is `invalid_note`.
  """
  def change_mine(id, actor, change) do
    with :ok <- NotPaired.check(actor),
         {:ok, note} <- mine(id, actor) do
      case change.(note) do
        {:ok, note} ->
          {:ok, %{note: present(note)}}

        {:error, %Ash.Error.Invalid{} = error} ->
          {:error, Refused.exception(code: "invalid_note", error: error)}

        error ->
          NotPaired.ended(error, actor)
      end
    end
  end
end

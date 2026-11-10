defmodule AshTemplate.Rooms.Report do
  @moduledoc """
  One signed-in person reporting someone else's room message
  (`AshTemplate.Rooms.Message`) to the site's team, with why: spam, abuse, text
  that tries to steer agents, or something else. An agent they paired reports for
  them. A person reports a message once; reporting it again answers their first
  report. Besides the reporter, only the site's operator reads a report
  (`:reported`, `AshTemplate.Rooms.Moderation`), and may remove the message; until
  then the message stays as it is. A report goes with its message when the
  message is deleted or removed.
  """

  use Ash.Resource,
    domain: AshTemplate.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Limits.LimitWrites
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Message

  @reasons [:spam, :abuse, :steers_agents, :other]

  postgres do
    table "room_message_reports"
    repo(AshTemplate.Repo)

    references do
      reference(:message, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :reason, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @reasons]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :message, Message, allow_nil?: false, public?: true

    belongs_to :reporter, HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :one_per_reporter, [:message_id, :reporter_id]
  end

  actions do
    defaults [:read]

    # Every report whose message is still in a room, newest first, for the site's
    # operator. A removed message takes its reports with it, so this is what is
    # still waiting to be looked at.
    read :reported do
      prepare build(sort: [inserted_at: :desc], load: [:message])
    end

    # Reporting a message again keeps the first report and its reason.
    create :send do
      accept [:message_id, :reason]
      upsert? true
      upsert_identity :one_per_reporter
      upsert_fields []
      change set_attribute(:reporter_id, actor(:human_account_id))

      # Only while the message is still here, and only when someone else wrote it.
      change fn changeset, context ->
        reporter = Ash.Changeset.get_attribute(changeset, :reporter_id)
        message_id = Ash.Changeset.get_attribute(changeset, :message_id)

        case Rooms.get_message(message_id, Ash.Context.to_opts(context)) do
          {:ok, %Message{human_account_id: ^reporter}} ->
            Ash.Changeset.add_error(changeset,
              field: :message_id,
              message: "You can't report your own message."
            )

          {:ok, %Message{}} ->
            changeset

          _gone ->
            Ash.Changeset.add_error(changeset,
              field: :message_id,
              message: "That message is no longer here."
            )
        end
      end

      change {LimitWrites,
              allowance: :report,
              field: :message_id,
              message: "You've sent a lot of reports this hour. Try again later."}
    end
  end

  # An agent's report rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create]
  end

  policies do
    # Only the site's operator reads everyone's reports, from a release command.
    bypass action(:reported) do
      authorize_if actor_attribute_equals(:role, :system)
    end

    policy action(:reported) do
      forbid_if always()
    end

    policy always() do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type(:read) do
      authorize_if expr(reporter_id == ^actor(:human_account_id))
    end
  end

  @doc "A report as its reporter's agent reads it."
  def public(%__MODULE__{} = report) do
    %{
      id: report.id,
      message_id: report.message_id,
      reason: report.reason,
      inserted_at: report.inserted_at
    }
  end
end

defmodule AshTemplate.Chat.Message do
  @moduledoc """
  One message in a chat conversation, as `mix ash_ai.gen.chat` generates it: a
  person's message, or the assistant's reply, which a job writes a few words at
  a time and publishes to the conversation's open pages as it goes.

  A paired agent writes for its person with an `operation_id`, which becomes the
  message's id, so a retry answers the message it already sent (`:earlier_send`).
  """

  use Ash.Resource,
    otp_app: :ash_template,
    domain: AshTemplate.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  attributes do
    timestamps()
    uuid_v7_primary_key :id, writable?: true

    attribute :text, :string do
      constraints allow_empty?: true, trim?: false, max_length: 4000
      public? true
      allow_nil? false
    end

    attribute :tool_calls, {:array, :map}
    attribute :tool_results, {:array, :map}

    attribute :source, AshTemplate.Chat.Message.Types.Source do
      allow_nil? false
      public? true
      default :user
    end

    attribute :complete, :boolean do
      allow_nil? false
      default true
    end
  end

  relationships do
    belongs_to :conversation, AshTemplate.Chat.Conversation do
      public? true
      allow_nil? false
    end

    belongs_to :response_to, __MODULE__ do
      public? true
    end

    has_one :response, __MODULE__ do
      public? true
      destination_attribute :response_to_id
    end
  end

  actions do
    defaults [:read, :destroy]

    read :for_conversation do
      pagination keyset?: true, required?: false
      argument :conversation_id, :uuid, allow_nil?: false

      prepare build(default_sort: [inserted_at: :desc])
      filter expr(conversation_id == ^arg(:conversation_id))
    end

    # The `:respond` job's own read of its message. Only AshOban may use it, so a
    # job whose agent was unpaired after sending still reaches `:fail_response`.
    read :job_read

    # The message the actor's person already sent with this id, so a retry
    # answers the first send.
    read :earlier_send do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and source == :user)
    end

    create :create do
      accept [:text]

      validate match(:text, ~r/\S/) do
        message "Message cannot be empty"
      end

      argument :conversation_id, :uuid do
        public? false
      end

      argument :operation_id, :uuid do
        public? false
      end

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

      change {AshTemplate.Limits.LimitWrites, allowance: :chat_message, field: :text}
      change AshTemplate.Chat.Message.Changes.CreateConversationIfNotProvided
      change run_oban_trigger(:respond)
    end

    update :respond do
      accept []
      require_atomic? false
      transaction? false
      change AshTemplate.Chat.Message.Changes.Respond
    end

    # Called by the `:respond` trigger once its job has failed for good.
    update :fail_response do
      accept []
      argument :error, :term
      require_atomic? false
      change AshTemplate.Chat.Message.Changes.FailResponse
    end

    create :upsert_response do
      upsert? true
      accept [:id, :response_to_id, :conversation_id]
      argument :complete, :boolean, default: false
      argument :text, :string, allow_nil?: false, constraints: [trim?: false, allow_empty?: true]
      argument :tool_calls, {:array, :map}
      argument :tool_results, {:array, :map}

      # if updating
      #   if complete, set the text to the provided text
      #   if streaming still, add the text to the provided text
      change atomic_update(
               :text,
               {:atomic,
                expr(
                  if ^arg(:complete) do
                    ^arg(:text)
                  else
                    text <> ^arg(:text)
                  end
                )}
             )

      change atomic_update(
               :tool_calls,
               {:atomic,
                expr(
                  if is_nil(^arg(:tool_calls)) do
                    tool_calls
                  else
                    fragment(
                      "? || ?",
                      tool_calls,
                      type(
                        ^arg(:tool_calls),
                        {:array, :map}
                      )
                    )
                  end
                )}
             )

      change atomic_update(
               :tool_results,
               {:atomic,
                expr(
                  if is_nil(^arg(:tool_results)) do
                    tool_results
                  else
                    fragment(
                      "? || ?",
                      tool_results,
                      type(
                        ^arg(:tool_results),
                        {:array, :map}
                      )
                    )
                  end
                )}
             )

      # if creating, set the text attribute to the provided text
      change set_attribute(:text, arg(:text))
      change set_attribute(:complete, arg(:complete))
      change set_attribute(:source, :agent)
      change set_attribute(:tool_results, arg(:tool_results))
      change set_attribute(:tool_calls, arg(:tool_calls))

      # on update, only set complete to its new value
      upsert_fields [:complete]
    end
  end

  postgres do
    table "chat_messages"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:conversation_id, :inserted_at])
    end
  end

  # An agent's send rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create]
  end

  policies do
    bypass AshAi.Checks.ActorIsAshAi do
      authorize_if always()
    end

    # An agent unpaired after sending may no longer read or answer its message, so
    # AshOban alone ends that reply with a line saying it failed.
    bypass action([:job_read, :fail_response]) do
      authorize_if AshOban.Checks.AshObanInteraction
    end

    policy always() do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy always() do
      authorize_if expr(conversation.human_account_id == ^actor(:human_account_id))
    end
  end

  calculations do
    calculate :needs_response, :boolean do
      calculation expr(source == :user and not exists(response))
    end
  end

  pub_sub do
    module AshTemplateWeb.Endpoint
    prefix "chat"

    publish :create, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{
          text: message.text,
          id: message.id,
          source: message.source,
          complete: message.complete,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        }
      end
    end

    publish :upsert_response, ["messages", :conversation_id] do
      transform fn %{data: message} ->
        %{
          text: message.text,
          id: message.id,
          source: message.source,
          complete: message.complete,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results
        }
      end
    end
  end

  oban do
    triggers do
      trigger :respond do
        actor_persister AshTemplate.Chat.ActorPersister
        action :respond
        worker_read_action :job_read
        on_error :fail_response
        on_error_fails_job? true
        # A job that gives up logs one safe line (RegentHttp.UnexpectedFailure), not raw text.
        log_errors? false
        log_final_error? false
        queue :chat_responses
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Chat.Message.Workers.Respond
        scheduler_module_name AshTemplate.Chat.Message.Schedulers.Respond
        where expr(needs_response)
      end
    end
  end
end

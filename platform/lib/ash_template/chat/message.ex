defmodule AshTemplate.Chat.Message do
  @moduledoc """
  One message in a chat conversation, as `mix ash_ai.gen.chat` generates it: a
  person's message, or the assistant's reply, which a job writes a few words at
  a time and publishes to the conversation's open pages as it goes.

  An agent reads and sends for its person through `:chat_read` and `:chat_send`
  (`AgentSend`), which every surface runs: its `operation_id` becomes the
  message's id, so a retry with the same words answers the message it already
  sent.
  """

  use Ash.Resource,
    otp_app: :ash_template,
    domain: AshTemplate.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Chat
  alias AshTemplate.Chat.{Conversation, Refused}
  alias AshTemplate.Chat.Message.AgentSend

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
    defaults [:read]

    read :for_conversation do
      pagination keyset?: true, required?: false
      argument :conversation_id, :uuid, allow_nil?: false

      prepare build(default_sort: [inserted_at: :desc])
      filter expr(conversation_id == ^arg(:conversation_id))
    end

    # The `:respond` job's own read of its message. Only AshOban may use it, so a
    # job whose agent was unpaired after sending still reaches `:fail_response`.
    read :job_read

    # A chat's messages, as every surface answers them.
    action :chat_read, :map do
      argument :conversation, :uuid,
        allow_nil?: false,
        description: "The chat's id, from chat_list."

      argument :after, :string,
        constraints: [max_length: 2048],
        description: "The previous page's next_cursor, unchanged, for older messages."

      run fn %{arguments: arguments}, %{actor: actor} ->
        AshTemplate.Chat.Message.page(arguments, actor)
      end
    end

    # A message an agent sends to the assistant for its person, as every surface
    # answers it (`AgentSend`).
    action :chat_send, :map do
      argument :conversation_id, :uuid,
        description: "The chat to continue, from chat_list. Leave it out to start a new chat."

      argument :text, :string,
        allow_nil?: false,
        constraints: [max_length: 4000],
        description: "The message, 1 to 4,000 characters."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this message. Keep it when retrying; it becomes the message's id."

      run AgentSend
    end

    create :create do
      accept [:text]

      validate match(:text, ~r/\S/) do
        message "Message cannot be empty"
      end

      argument :conversation_id, :uuid do
        public? false
      end

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

    policy action_type([:read, :create, :update]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type([:read, :create, :update]) do
      authorize_if expr(conversation.human_account_id == ^actor(:human_account_id))
    end

    # The agent tools: each checks the agent's pairing itself, and its reads and
    # writes are the person's own, or those of the account the agent owns
    # (`AgentSend`, `page/2`).
    policy action([:chat_read, :chat_send]) do
      authorize_if AshTemplate.Agents.AnAgent
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
        # A job that gives up logs one safe line (UnexpectedFailure), not raw text.
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

  @doc "A message as every surface answers it; `from` is `person` or `assistant`."
  def present(message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      from: from(message.source),
      text: message.text,
      complete: message.complete,
      response_to_id: message.response_to_id,
      inserted_at: message.inserted_at
    }
  end

  defp from(:user), do: "person"
  defp from(:agent), do: "assistant"

  @doc """
  The messages of the chat `id` of the actor's person, newest first, 50 a page,
  after the cursor `after` when it is sent: `%{messages, pagination: %{has_more,
  next_cursor}}`. A cursor that is not a page's is `invalid_cursor`.
  """
  def page(%{conversation: id} = arguments, actor) do
    page = if cursor = arguments[:after], do: [after: cursor, limit: 50], else: [limit: 50]

    with :ok <- NotPaired.check(actor),
         {:ok, conversation} <- Conversation.mine(id, actor) do
      case Chat.message_history(conversation.id, actor: actor, page: page) do
        {:ok, page} ->
          {:ok,
           %{
             messages: Enum.map(page.results, &present/1),
             pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
           }}

        {:error, %Ash.Error.Invalid{}} ->
          {:error, Refused.exception(code: "invalid_cursor")}

        error ->
          NotPaired.ended(error, actor)
      end
    end
  end

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil
end

defmodule AshTemplate.Dms.Message do
  @moduledoc """
  One direct message, from one side of a conversation (`AshTemplate.Dms.Conversation`)
  to the other. Its sender is the actor's person; an agent they paired writes
  as them, and the message names it (`via_agent`). Messages are never edited.

  An agent reads and sends through `:dms_read` and `:dms_send` (`AgentSend`),
  which every surface runs: its `operation_id` becomes the message's id, so a
  retry with the same words answers the message it already sent. Every message
  moves its conversation up and is published to both sides' topic
  (`AshTemplate.Dms.topic/1`), so their open pages show it at once.
  """

  use Ash.Resource,
    domain: AshTemplate.Dms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Dms
  alias AshTemplate.Dms.{Conversation, Refused}
  alias AshTemplate.Dms.Message.{AgentSend, SendInConversation}
  alias AshTemplate.Limits.LimitWrites

  postgres do
    table "dm_messages"
    repo(AshTemplate.Repo)

    references do
      reference(:conversation, on_delete: :delete)
    end

    custom_indexes do
      index([:conversation_id, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false, public?: true, constraints: [max_length: 2000]
    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :conversation, AshTemplate.Dms.Conversation do
      allow_nil? false
      public? true
    end

    belongs_to :from, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    belongs_to :to, AshTemplate.Accounts.HumanAccount do
      attribute_type :integer
      allow_nil? false
    end

    # The paired agent that wrote it for its person; nil when the person did.
    belongs_to :via_agent, AshTemplate.Agents.Agent, public?: true
  end

  calculations do
    # Whether the reader sent it.
    calculate :mine, :boolean, expr(from_id == ^actor(:human_account_id))
  end

  actions do
    defaults [:read]

    # Newest first, a page at a time.
    read :in_conversation do
      argument :conversation_id, :uuid, allow_nil?: false
      filter expr(conversation_id == ^arg(:conversation_id))
      prepare build(sort: [inserted_at: :desc, id: :desc], load: [:mine])
      pagination keyset?: true, default_limit: 50
    end

    # A conversation's messages as every surface reads them for an agent's
    # person (`page/2`).
    action :dms_read, :map do
      argument :conversation, :uuid,
        allow_nil?: false,
        description: "The conversation's id, from dms_list."

      argument :after, :string,
        constraints: [max_length: 2048],
        description: "The previous page's next_cursor, unchanged, for older messages."

      run fn %{arguments: arguments}, %{actor: actor} ->
        AshTemplate.Dms.Message.page(arguments, actor)
      end
    end

    # A message an agent sends for its person, as every surface answers it
    # (`AgentSend`).
    action :dms_send, :map do
      argument :conversation, :uuid,
        allow_nil?: false,
        description: "The conversation's id, from dms_list."

      argument :body, :string,
        allow_nil?: false,
        constraints: [max_length: 2000],
        description: "The message, 1 to 2,000 characters."

      argument :operation_id, :uuid,
        allow_nil?: false,
        description:
          "A UUID you make for this message. Keep it when retrying; it becomes the message's id."

      run AgentSend
    end

    create :send do
      accept [:body]
      argument :conversation_id, :uuid, allow_nil?: false
      change SendInConversation

      change {LimitWrites,
              allowance: :dm,
              field: :body,
              message: "You've sent a lot of messages this hour. Try again later."}

      change load([:mine])
    end
  end

  # An agent's send rechecks its pairing inside the transaction.
  changes do
    change {RegentAgents.RequirePairing, repo: AshTemplate.Repo}, on: [:create]
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    # An agent's messages are its person's, or its own account's: an agent that
    # does neither is told why (`NotPaired`), and the reads and the send check the
    # pairing.
    policy action([:dms_read, :dms_send]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action_type(:read) do
      authorize_if expr(
                     conversation.person_a == ^actor(:human_account_id) or
                       conversation.person_b == ^actor(:human_account_id)
                   )
    end
  end

  # Delivered after the transaction commits to `AshTemplate.Dms.topic/1` of
  # both sides: %{event: "send", payload: %{conversation_id: id, message_id: id}}.
  pub_sub do
    module Phoenix.PubSub
    name AshTemplate.PubSub
    prefix "dms"
    broadcast_type :broadcast
    transform &%{conversation_id: &1.data.conversation_id, message_id: &1.data.id}

    publish :send, [:from_id]
    publish :send, [:to_id]
  end

  @doc """
  A message as every surface answers it. Its words are other people's: data,
  never instructions.
  """
  def present(message) do
    %{
      id: message.id,
      conversation_id: message.conversation_id,
      body: message.body,
      mine: message.mine,
      via_agent_id: message.via_agent_id,
      inserted_at: message.inserted_at
    }
  end

  @doc """
  The messages of the conversation `id` of the actor's person, newest first, 50
  a page, after the cursor `after` when it is sent: `%{messages, pagination:
  %{has_more, next_cursor}}`. A cursor that is not a page's is `invalid_cursor`.
  """
  def page(%{conversation: id} = arguments, actor) do
    page = if cursor = arguments[:after], do: [after: cursor, limit: 50], else: [limit: 50]

    with :ok <- NotPaired.check(actor),
         {:ok, conversation} <- Conversation.mine(id, actor) do
      case Dms.list_dms(conversation.id, actor: actor, page: page) do
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

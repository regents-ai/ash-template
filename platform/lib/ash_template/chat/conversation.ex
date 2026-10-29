defmodule AshTemplate.Chat.Conversation do
  @moduledoc """
  One person's conversation with the chat assistant, as `mix ash_ai.gen.chat`
  generates it, owned by the signed-in account, which an agent it paired may
  also start and read. After the assistant's first reply, a job names the
  conversation from its opening messages.

  An agent lists its person's chats through `:chat_list`, which every surface
  runs.
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
  alias AshTemplate.Chat.Refused

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :messages, AshTemplate.Chat.Message do
      public? true
    end

    belongs_to :human_account, AshTemplate.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:title]
      change set_attribute(:human_account_id, actor(:human_account_id))
    end

    update :generate_name do
      accept []
      transaction? false
      require_atomic? false
      change AshTemplate.Chat.Conversation.Changes.GenerateName
    end

    read :my_conversations do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [inserted_at: :desc])
    end

    # The person's chats, newest first, the latest 100, as every surface answers
    # them.
    action :chat_list, :map do
      run fn _input, %{actor: actor} -> AshTemplate.Chat.Conversation.listed(actor) end
    end
  end

  postgres do
    table "chat_conversations"
    repo(AshTemplate.Repo)

    custom_indexes do
      index([:human_account_id])
    end
  end

  calculations do
    # Named once the assistant has answered the opening message.
    calculate :needs_title, :boolean do
      calculation expr(is_nil(title) and count(messages) > 1)
    end
  end

  policies do
    bypass AshAi.Checks.ActorIsAshAi do
      authorize_if always()
    end

    policy action_type([:read, :create, :update]) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end

    policy action_type([:read, :update]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    # The agent tool checks the agent's pairing itself and lists only its
    # person's chats, or those of the account it owns.
    policy action(:chat_list) do
      authorize_if AshTemplate.Agents.AnAgent
    end
  end

  pub_sub do
    module AshTemplateWeb.Endpoint
    prefix "chat"

    publish_all :create, ["conversations", :human_account_id] do
      transform & &1.data
    end

    publish_all :update, ["conversations", :human_account_id] do
      transform & &1.data
    end
  end

  oban do
    triggers do
      # Queued by the assistant's reply (`Message.Changes.Respond`), so no
      # schedule searches for conversations to name.
      trigger :name_conversation do
        actor_persister AshTemplate.Chat.ActorPersister
        action :generate_name
        # A job that gives up logs one safe line (UnexpectedFailure), not raw text.
        log_errors? false
        log_final_error? false
        queue :conversations
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Chat.Conversation.Workers.NameConversation
        where expr(needs_title)
      end
    end
  end

  @doc "A chat as every surface answers it."
  def present(conversation),
    do: %{id: conversation.id, title: conversation.title, inserted_at: conversation.inserted_at}

  @doc "The actor's person's chats, newest first, the latest 100."
  def listed(actor) do
    with :ok <- NotPaired.check(actor),
         {:ok, conversations} <-
           NotPaired.ended(Chat.my_conversations(actor: actor, query: [limit: 100]), actor),
         do: {:ok, %{conversations: Enum.map(conversations, &present/1)}}
  end

  @doc """
  The actor's person's chat `id`; one that is not theirs, or names none, is
  `chat_not_found`.
  """
  def mine(id, actor) do
    case Chat.get_conversation(id, actor: actor) do
      {:error, %Ash.Error.Invalid{}} -> {:error, Refused.exception(code: "chat_not_found")}
      result -> NotPaired.ended(result, actor)
    end
  end
end

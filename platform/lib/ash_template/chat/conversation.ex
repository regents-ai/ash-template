defmodule AshTemplate.Chat.Conversation do
  @moduledoc """
  One person's conversation with the chat assistant, as `mix ash_ai.gen.chat`
  generates it, owned by the signed-in account. After the assistant's first
  reply, a job names the conversation from its opening messages.
  """

  use Ash.Resource,
    otp_app: :ash_template,
    domain: AshTemplate.Chat,
    extensions: [AshOban],
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

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
    defaults [:read, :destroy]

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

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :human)
    end

    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
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
        queue :conversations
        lock_for_update? false
        scheduler_cron false
        worker_module_name AshTemplate.Chat.Conversation.Workers.NameConversation
        where expr(needs_title)
      end
    end
  end
end

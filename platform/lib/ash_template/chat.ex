defmodule AshTemplate.Chat do
  @moduledoc """
  Chat with an assistant, as `mix ash_ai.gen.chat` generates it: each person's
  conversations and their messages, the job that writes each reply and the one
  that names a conversation, and the tools the assistant may call.
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi, AshPhoenix]

  resources do
    resource AshTemplate.Chat.Conversation do
      define :create_conversation, action: :create
      define :get_conversation, action: :read, get_by: [:id]
      define :my_conversations
    end

    resource AshTemplate.Chat.Message do
      define :message_history,
        action: :for_conversation,
        args: [:conversation_id],
        default_options: [query: [sort: [inserted_at: :desc]]]

      define :create_message, action: :create
    end
  end

  tools do
    tool :chat_list_conversations, AshTemplate.Chat.Conversation, :my_conversations do
      description "List chat conversations visible to the current actor."
    end

    tool :chat_message_history, AshTemplate.Chat.Message, :for_conversation do
      description "Read chat messages for a conversation_id."
    end
  end
end

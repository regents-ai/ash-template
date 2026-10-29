defmodule AshTemplate.Chat do
  @moduledoc """
  Chat with an assistant, as `mix ash_ai.gen.chat` generates it: each person's
  conversations and their messages, the job that writes each reply and the one
  that names a conversation, and the tools the assistant may call. What an agent
  does in its person's chats is also a hosted agent tool (`tools`).
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi, AshPhoenix]

  @doc "The tools the assistant calls in a reply; the hosted MCP server never serves them."
  def assistant_tools, do: [:chat_list_conversations, :chat_message_history]

  resources do
    resource AshTemplate.Chat.Conversation do
      define :create_conversation, action: :create
      define :get_conversation, action: :read, get_by: [:id]
      define :my_conversations
      define :chat_list, action: :chat_list
    end

    resource AshTemplate.Chat.Message do
      define :message_history,
        action: :for_conversation,
        args: [:conversation_id],
        default_options: [query: [sort: [inserted_at: :desc]]]

      define :create_message, action: :create
      define :get_message, action: :read, get_by: [:id], not_found_error?: true
      define :chat_read, action: :chat_read, args: [:conversation]
      define :chat_send, action: :chat_send
    end
  end

  # The assistant's own tools (`assistant_tools/0`), and the hosted agent tools:
  # each runs the same action as its HTTP route, its browser tool and its
  # regents-cli command, and is named after them (`AshTemplateWeb.Capabilities`
  # checks both).
  tools do
    tool :chat_list_conversations, AshTemplate.Chat.Conversation, :my_conversations do
      description "List chat conversations visible to the current actor."
    end

    tool :chat_message_history, AshTemplate.Chat.Message, :for_conversation do
      description "Read chat messages for a conversation_id."
    end

    tool :chat_list, AshTemplate.Chat.Conversation, :chat_list do
      description AshTemplate.Descriptions.hosted(:chat_list)
    end

    tool :chat_read, AshTemplate.Chat.Message, :chat_read do
      description AshTemplate.Descriptions.hosted(:chat_read)
    end

    tool :chat_send, AshTemplate.Chat.Message, :chat_send do
      description AshTemplate.Descriptions.hosted(:chat_send)
    end
  end
end

defmodule AshTemplate.Dms do
  @moduledoc """
  Direct messages: one person writing privately to another. Two people share
  one conversation (`AshTemplate.Dms.Conversation`), opened from a room
  message the other person wrote, so no page ever handles another account's
  id. Each message is a line in it (`AshTemplate.Dms.Message`). Only the two
  people in a conversation, or an agent one of them paired, read or write it.

  The rules, as Keyfleet's direct messages have them, for people instead of
  Keys:

  1. **Blocking is per conversation and per side.** A blocked person's
     messages still save, and the conversation moves from the blocker's
     messages to their Blocked list (`Conversation`'s `:inbox`, its `blocked`
     argument). Unblocking moves it back.
  2. **No notifications.** A new message tells only the pages open on either
     person's messages (`topic/1`). Nothing else is sent.
  3. **Words only.** A file is sent as a link in the words.
  4. **A person sends at most 300 messages an hour** (`:dm` in
     `AshTemplate.Limits`).
  """

  use Ash.Domain, extensions: [AshPhoenix]

  resources do
    resource AshTemplate.Dms.Conversation do
      define :list_conversations, action: :inbox, args: [{:optional, :blocked}]
      define :get_conversation, action: :read, get_by: [:id], not_found_error?: false
      define :open_conversation, action: :open, args: [:message_id]
      define :block_conversation, action: :block
      define :unblock_conversation, action: :unblock
    end

    resource AshTemplate.Dms.Message do
      define :list_dms, action: :in_conversation, args: [:conversation_id]
      define :get_dm, action: :read, get_by: [:id], not_found_error?: false
      define :get_earlier_dm, action: :earlier_send, args: [:id], not_found_error?: false
      define :send_dm, action: :send, args: [:conversation_id]
    end
  end

  @doc """
  The topic each new message and each block in a person's conversations is
  published on, after it commits: `%{event: "send", payload: %{conversation_id:
  id, message_id: id}}`, or `%{event: "block" | "unblock", payload:
  %{conversation_id: id}}`.
  """
  def topic(human_account_id), do: "dms:#{human_account_id}"
end

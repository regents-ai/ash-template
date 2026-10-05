defmodule AshTemplate.Rooms do
  @moduledoc "The site's chat rooms: messages anyone can read, and the people each reader has muted."

  use Ash.Domain

  resources do
    resource AshTemplate.Rooms.Message do
      define :list_room_messages, action: :in_room, args: [:room]
      define :search_messages, action: :search, args: [:text]
      define :get_message, action: :read, get_by: [:id], not_found_error?: false
      define :post_message, action: :post
      define :edit_message, action: :edit
      define :delete_message, action: :destroy
    end

    resource AshTemplate.Rooms.Mute do
      define :list_my_mutes, action: :mine
      define :get_my_mute, action: :read, get_by: [:id], not_found_error?: false
      define :mute_author, action: :mute, args: [:message_id]
      define :unmute, action: :destroy
    end
  end
end

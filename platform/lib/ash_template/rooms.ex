defmodule AshTemplate.Rooms do
  @moduledoc "The chat rooms: rooms people start, messages anyone can read, the likes people give them, and the people each reader has muted."

  use Ash.Domain, extensions: [AshPhoenix]

  resources do
    resource AshTemplate.Rooms.Room do
      define :list_rooms, action: :list
      define :get_room, action: :read, get_by: [:slug], not_found_error?: false
      define :get_started_room, action: :started_by_actor, args: [:slug], not_found_error?: false
      define :search_rooms, action: :search, args: [:text]
      define :create_room, action: :create
      define :set_room_topic, action: :set_topic
    end

    resource AshTemplate.Rooms.Message do
      define :list_room_messages, action: :in_room, args: [:room]
      define :search_messages, action: :search, args: [:text]
      define :get_message, action: :read, get_by: [:id], not_found_error?: false

      define :get_room_message,
        action: :one_in_room,
        args: [:room, :id],
        not_found_error?: false

      define :get_earlier_post,
        action: :earlier_post,
        args: [:room, :operation_id],
        not_found_error?: false

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

    resource AshTemplate.Rooms.Like do
      define :like_message, action: :like, args: [:message_id]
      define :get_my_like, action: :mine, args: [:message_id], not_found_error?: false
      define :unlike, action: :destroy
    end
  end
end

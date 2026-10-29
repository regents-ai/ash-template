defmodule AshTemplate.Rooms do
  @moduledoc """
  The chat rooms: rooms people start, messages anyone can read, the likes people
  give them, the people each reader has muted, and the messages people report.
  Everything an agent does in the rooms for its person, and its person's mutes,
  are also hosted agent tools (`tools`).
  """

  use Ash.Domain, otp_app: :ash_template, extensions: [AshAi, AshPhoenix]

  resources do
    resource AshTemplate.Rooms.Room do
      define :list_rooms, action: :list
      define :rooms_list, action: :rooms_list
      define :get_room, action: :read, get_by: [:slug], not_found_error?: false
      define :get_started_room, action: :started_by_actor, args: [:slug], not_found_error?: false
      define :search_rooms, action: :search, args: [:text]
      define :create_room, action: :create
      define :set_room_topic, action: :set_topic
      define :rooms_create, action: :rooms_create
      define :rooms_topic, action: :rooms_topic, args: [:room]
    end

    resource AshTemplate.Rooms.Message do
      define :list_room_messages, action: :in_room, args: [:room]
      define :search_messages, action: :search, args: [:text]
      define :get_message, action: :read, get_by: [:id], not_found_error?: false

      define :get_room_message,
        action: :one_in_room,
        args: [:room, :id],
        not_found_error?: false

      define :room_messages, action: :room_messages, args: [:room]
      define :rooms_message, action: :rooms_message, args: [:room, :id]
      define :rooms_search, action: :rooms_search, args: [:text]
      define :agent_post, action: :agent_post, args: [:room]
      define :rooms_edit, action: :rooms_edit, args: [:room, :id]
      define :rooms_delete, action: :rooms_delete, args: [:room, :id]
      define :rooms_like, action: :rooms_like, args: [:room, :id]
      define :rooms_unlike, action: :rooms_unlike, args: [:room, :id]
      define :rooms_report, action: :rooms_report, args: [:room, :id]
      define :post_message, action: :post
      define :edit_message, action: :edit
      define :delete_message, action: :destroy
    end

    resource AshTemplate.Rooms.Mute do
      define :list_my_mutes, action: :mine
      define :mutes_list, action: :mutes_list
      define :get_my_mute, action: :read, get_by: [:id], not_found_error?: false
      define :mute_author, action: :mute, args: [:message_id]
      define :unmute, action: :destroy
      define :mutes_add, action: :mutes_add
      define :mutes_remove, action: :mutes_remove, args: [:id]
    end

    resource AshTemplate.Rooms.Like do
      define :like_message, action: :like, args: [:message_id]
      define :get_my_like, action: :mine, args: [:message_id], not_found_error?: false
      define :unlike, action: :destroy
    end

    resource AshTemplate.Rooms.Report do
      define :report_message, action: :send, args: [:message_id, :reason]
    end
  end

  # The hosted agent tools: each runs the same action as its HTTP route, its
  # browser tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :rooms_list, AshTemplate.Rooms.Room, :rooms_list do
      description AshTemplate.Descriptions.hosted(:rooms_list)
    end

    tool :rooms_messages, AshTemplate.Rooms.Message, :room_messages do
      description AshTemplate.Descriptions.hosted(:rooms_messages)
    end

    tool :rooms_post, AshTemplate.Rooms.Message, :agent_post do
      description AshTemplate.Descriptions.hosted(:rooms_post)
    end

    tool :rooms_create, AshTemplate.Rooms.Room, :rooms_create do
      description AshTemplate.Descriptions.hosted(:rooms_create)
    end

    tool :rooms_topic, AshTemplate.Rooms.Room, :rooms_topic do
      description AshTemplate.Descriptions.hosted(:rooms_topic)
    end

    tool :rooms_edit, AshTemplate.Rooms.Message, :rooms_edit do
      description AshTemplate.Descriptions.hosted(:rooms_edit)
    end

    tool :rooms_delete, AshTemplate.Rooms.Message, :rooms_delete do
      description AshTemplate.Descriptions.hosted(:rooms_delete)
    end

    tool :rooms_like, AshTemplate.Rooms.Message, :rooms_like do
      description AshTemplate.Descriptions.hosted(:rooms_like)
    end

    tool :rooms_unlike, AshTemplate.Rooms.Message, :rooms_unlike do
      description AshTemplate.Descriptions.hosted(:rooms_unlike)
    end

    tool :rooms_report, AshTemplate.Rooms.Message, :rooms_report do
      description AshTemplate.Descriptions.hosted(:rooms_report)
    end

    tool :rooms_message, AshTemplate.Rooms.Message, :rooms_message do
      description AshTemplate.Descriptions.hosted(:rooms_message)
    end

    tool :rooms_search, AshTemplate.Rooms.Message, :rooms_search do
      description AshTemplate.Descriptions.hosted(:rooms_search)
    end

    tool :mutes_list, AshTemplate.Rooms.Mute, :mutes_list do
      description AshTemplate.Descriptions.hosted(:mutes_list)
    end

    tool :mutes_add, AshTemplate.Rooms.Mute, :mutes_add do
      description AshTemplate.Descriptions.hosted(:mutes_add)
    end

    tool :mutes_remove, AshTemplate.Rooms.Mute, :mutes_remove do
      description AshTemplate.Descriptions.hosted(:mutes_remove)
    end
  end
end

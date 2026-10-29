defmodule AshTemplate.Activity do
  @moduledoc """
  What has happened for each signed-in person: their notifications, newest
  first. A paired agent's read of them, and its marking them all read, are also
  hosted agent tools (`tools`).
  """

  use Ash.Domain, extensions: [AshAi]

  alias AshTemplate.Activity.Notification

  resources do
    resource Notification do
      define :list_my_notifications, action: :mine
      define :activity_list, action: :activity_list, args: [:after]
      define :activity_mark_read, action: :activity_mark_read
    end
  end

  # The hosted agent tool runs the same action as its HTTP route, its browser
  # tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :activity_list, Notification, :activity_list do
      description AshTemplate.Descriptions.hosted(:activity_list)
    end

    tool :activity_mark_read, Notification, :activity_mark_read do
      description AshTemplate.Descriptions.hosted(:activity_mark_read)
    end
  end

  @doc "How many of the actor's notifications they have not read yet."
  def count_unread(opts),
    do: Notification |> Ash.Query.for_read(:unread, %{}, opts) |> Ash.count(opts)

  @doc "Marks every notification the actor has not read as read."
  def mark_all_read(opts) do
    Notification
    |> Ash.Query.for_read(:unread, %{}, opts)
    |> Ash.bulk_update(:mark_read, %{}, Keyword.merge(opts, notify?: true, return_errors?: true))
  end
end

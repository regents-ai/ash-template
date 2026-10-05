defmodule AshTemplate.Activity do
  @moduledoc "What has happened for each signed-in person: their notifications, newest first."

  use Ash.Domain

  require Ash.Query

  alias AshTemplate.Activity.Notification

  resources do
    resource Notification do
      define :list_my_notifications, action: :mine
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

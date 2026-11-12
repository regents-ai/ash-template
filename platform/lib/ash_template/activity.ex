defmodule AshTemplate.Activity do
  @moduledoc "What has happened for each signed-in person: their notifications, newest first."

  use Ash.Domain

  alias AshTemplate.Activity.Notification

  resources do
    resource Notification do
      define :list_my_notifications, action: :mine
    end
  end

  @doc "How many of the actor's notifications they have not read yet."
  def count_unread(opts),
    do: Notification |> Ash.Query.for_read(:unread, %{}, opts) |> Ash.count(opts)

  @doc """
  Marks every notification the actor has not read as read, in one statement, then
  tells their open pages once on `Notification.topic/1` (event `"mark_all_read"`),
  so each page recounts its bell once however many were marked.
  """
  def mark_all_read(opts) do
    result =
      Notification
      |> Ash.Query.for_read(:unread, %{}, opts)
      |> Ash.bulk_update(:mark_read, %{}, Keyword.put(opts, :return_errors?, true))

    if result.status == :success, do: Notification.all_read(opts[:actor].human_account_id)
    result
  end
end

defmodule AshTemplate.Rooms.Moderation do
  @moduledoc """
  What the site's operator does about reported room messages: read the reports,
  and remove a message with a reason. Each is an Ash action only the system
  actor may run (`AshTemplate.Rooms.Report`, `:reported`;
  `AshTemplate.Rooms.Message`, `:remove`), reached from a release command
  (`AshTemplate.Release.room_reports/0` and `remove_room_message/2`). No page
  and no agent tool reaches them.
  """

  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms

  @type reported :: %{
          message: Rooms.Message.t(),
          reports: pos_integer(),
          reasons: %{atom() => pos_integer()}
        }

  @doc "Every reported message still in a room, most reported first, with its reasons counted."
  @spec reported() :: {:ok, [reported()]} | {:error, term()}
  def reported do
    with {:ok, reports} <- Rooms.list_reports(actor: %System{}) do
      {:ok,
       reports
       |> Enum.group_by(& &1.message_id)
       |> Enum.map(fn {_id, [%{message: message} | _] = reports} ->
         %{
           message: message,
           reports: length(reports),
           reasons: Enum.frequencies_by(reports, & &1.reason)
         }
       end)
       |> Enum.sort_by(&{-&1.reports, &1.message.inserted_at})}
    end
  end

  @doc """
  Removes the room message `message_id` for `reason`, recording the removal in
  the same transaction. Its likes and reports go with it, and every open page
  of its room drops it. `{:error, :not_found}` when no such message is left.
  """
  @spec remove(String.t(), String.t()) ::
          {:ok, Rooms.Message.t()} | {:error, :not_found} | {:error, term()}
  def remove(message_id, reason) do
    case Rooms.get_message(message_id, actor: %System{}) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, message} ->
        with :ok <- Rooms.remove_message(message, reason, actor: %System{}), do: {:ok, message}

      {:error, %Ash.Error.Invalid{}} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, error}
    end
  end
end

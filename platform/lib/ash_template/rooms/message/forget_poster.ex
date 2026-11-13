defmodule AshTemplate.Rooms.Message.ForgetPoster do
  @moduledoc """
  Takes a person off a room's posters (`AshTemplate.Rooms.Poster`) once their
  last message there is gone, by their own delete or the operator's removal, in
  the delete's own transaction, so a mention there no longer finds them. One
  statement removes every name they posted under in the room, and only when no
  message of theirs is left in it. Posting again records them again
  (`AshTemplate.Rooms.Message.RecordPoster`). An agent posting as itself has no
  poster to remove.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Message, Poster}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn
      _changeset, %{human_account_id: nil} = message -> {:ok, message}
      _changeset, message -> forget(message)
    end)
  end

  defp forget(%{room: room, human_account_id: id} = message) do
    result =
      Poster
      |> Ash.Query.filter(
        room == ^room and human_account_id == ^id and
          not exists(Message, room == ^room and human_account_id == ^id)
      )
      |> Rooms.forget_posters(
        actor: %System{},
        bulk_options: [strategy: :atomic, return_errors?: true, stop_on_error?: true]
      )

    case result do
      %Ash.BulkResult{status: :success} -> {:ok, message}
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end

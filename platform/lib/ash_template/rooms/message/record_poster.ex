defmodule AshTemplate.Rooms.Message.RecordPoster do
  @moduledoc """
  Records the name a person posts under in the room (`AshTemplate.Rooms.Poster`),
  in the post's own transaction, so a mention of them finds them from their
  first post on. A name already recorded writes nothing.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.Poster

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      case Poster.name(message) do
        nil -> {:ok, message}
        name -> record(message, name)
      end
    end)
  end

  defp record(message, name) do
    result =
      Rooms.record_poster(
        [%{room: message.room, human_account_id: message.human_account_id, name: name}],
        actor: %System{},
        bulk_options: [return_records?: false, return_errors?: true, stop_on_error?: true]
      )

    case result do
      %Ash.BulkResult{status: :success} -> {:ok, message}
      %Ash.BulkResult{errors: errors} -> {:error, errors}
    end
  end
end

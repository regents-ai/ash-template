defmodule AshTemplate.Rooms.Message.RoomMessages do
  @moduledoc """
  One page of a room's messages, newest first, as every surface answers it:
  `%{messages: [Message.present/1], pagination: %{has_more, next_cursor}}`. It
  reads as a signed-out reader does, whoever asks, so every surface answers the
  same page for the same input.
  """

  use Ash.Resource.Actions.Implementation

  alias AshTemplate.Rooms
  alias AshTemplate.Rooms.{Message, Refused, Room}

  @impl true
  def run(input, _opts, _context) do
    %{room: slug} = input.arguments
    kind = input.arguments[:author_kind]

    # A limit or cursor left out is left out of the page, which then has the
    # read's own 50 a page and starts at the newest.
    page =
      Enum.reject(
        [after: input.arguments[:after], limit: input.arguments[:limit]],
        &is_nil(elem(&1, 1))
      )

    with {:ok, %Room{} = room} <- Rooms.get_room(slug),
         {:ok, page} <- Rooms.list_room_messages(room.slug, %{author_kind: kind}, page: page) do
      {:ok,
       %{
         messages: Enum.map(page.results, &Message.present/1),
         pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
       }}
    else
      {:ok, nil} -> {:error, Refused.exception(code: "room_not_found")}
      {:error, %Ash.Error.Invalid{}} -> {:error, Refused.exception(code: "invalid_cursor")}
      {:error, error} -> {:error, error}
    end
  end

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil
end

defmodule AshTemplate.Rooms.Message.SquashBlankLines do
  @moduledoc """
  Keeps at most one empty line between the lines of a message, so no message is
  mostly blank space. Line endings are stored as `\\n`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.update_change(changeset, :body, &squash/1)

  defp squash(body) when is_binary(body) do
    body
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/\n(?:[ \t]*\n){2,}/, "\n\n")
  end

  defp squash(body), do: body
end

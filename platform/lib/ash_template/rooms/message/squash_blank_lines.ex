defmodule AshTemplate.Rooms.Message.SquashBlankLines do
  @moduledoc """
  Keeps at most one empty line between the lines of a message, so no message is
  mostly blank space. Line endings are stored as `\\n`.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.update_change(changeset, :body, &squash/1)

  @doc "The text as a message stores it."
  @spec squash(String.t() | nil) :: String.t() | nil
  def squash(body) when is_binary(body) do
    body
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/\n(?:[ \t]*\n){2,}/, "\n\n")
  end

  def squash(body), do: body
end

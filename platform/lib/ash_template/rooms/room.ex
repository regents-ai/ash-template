defmodule AshTemplate.Rooms.Room do
  @moduledoc """
  The rooms this site runs. They are set here rather than stored: add a map to
  `@rooms` and its page, its place in the room list and its messages follow.
  """

  @rooms [
    %{slug: :general, name: "General", about: "Say hello and talk about anything."},
    %{slug: :help, name: "Help", about: "Ask how something works and help others find out."}
  ]

  @doc "Every room, in the order the room list shows them."
  def all, do: @rooms

  @doc "Each room's slug, the value a message stores."
  def slugs, do: Enum.map(@rooms, & &1.slug)

  @doc "The room an address names, such as `\"general\"` in `/rooms/general`."
  def fetch(slug) when is_binary(slug) do
    case Enum.find(@rooms, &(Atom.to_string(&1.slug) == slug)) do
      nil -> :error
      room -> {:ok, room}
    end
  end
end

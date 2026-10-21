defmodule AshTemplate.Rooms.Room.SlugFromName do
  @moduledoc """
  Sets a new room's slug from its name (`AshTemplate.Rooms.Room.slug/1`). A name
  with no letter from A to Z and no digit has no slug, and is refused.
  """

  use Ash.Resource.Change

  alias AshTemplate.Rooms.Room

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      nil ->
        changeset

      name ->
        case Room.slug(name) do
          "" ->
            Ash.Changeset.add_error(changeset,
              field: :name,
              message: "Use at least one letter from A to Z or a number."
            )

          slug ->
            Ash.Changeset.force_change_attribute(changeset, :slug, slug)
        end
    end
  end
end

defmodule AshTemplate.Rooms.Like.CountLike do
  @moduledoc """
  Moves the liked message's `like_count` by `:by` once the like is saved or
  taken back, in the same transaction (`AshTemplate.Rooms.Message`
  `:count_like`), so the count and the likes never disagree. A like given again
  saves nothing new (`upsert_fields []`), so it moves nothing. The message's
  notice of its new count goes out with the like's own, after the commit.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.System
  alias AshTemplate.Rooms

  @impl true
  def init(opts) do
    if opts[:by] in [1, -1], do: {:ok, opts}, else: {:error, "CountLike takes by: 1 or by: -1"}
  end

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, like -> count(like, opts[:by]) end)
  end

  # A like given again was an update of the one already there.
  defp count(%{__metadata__: %{upsert_action: :update}} = like, _by), do: {:ok, like}

  defp count(like, by) do
    case Rooms.count_like(like.message_id, by, actor: %System{}, return_notifications?: true) do
      {:ok, _message, notifications} -> {:ok, like, notifications}
      {:error, error} -> {:error, error}
    end
  end
end

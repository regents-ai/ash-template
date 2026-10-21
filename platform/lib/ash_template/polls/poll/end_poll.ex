defmodule AshTemplate.Polls.Poll.EndPoll do
  @moduledoc """
  Ends a poll that is still open. The poll is read again under a lock first:
  it may have closed or been ended since, and a vote being counted at that
  moment finishes before it ends (`AshTemplate.Polls.Vote.CastVote`).
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Polls
  alias AshTemplate.Polls.Poll

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn %{data: poll} = changeset ->
      # Ending it was authorized; this only reads it again under a lock.
      current =
        Poll
        |> Ash.Query.filter(id == ^poll.id)
        |> Ash.Query.lock(:for_update)
        |> Ash.read_one!(authorize?: false)

      if Polls.open?(current),
        do: Ash.Changeset.force_change_attribute(changeset, :ended_at, DateTime.utc_now()),
        else:
          Ash.Changeset.add_error(changeset, field: :ended_at, message: "This poll has closed.")
    end)
  end
end

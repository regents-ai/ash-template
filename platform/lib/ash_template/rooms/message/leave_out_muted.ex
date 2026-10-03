defmodule AshTemplate.Rooms.Message.LeaveOutMuted do
  @moduledoc "Leaves out messages from anyone the signed-in reader muted; a visitor sees every message."

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, %{actor: %{human_account_id: reader}}),
    do: Ash.Query.filter(query, not exists(author_mutes, muter_account_id == ^reader))

  def prepare(query, _opts, _context), do: query
end

defmodule AshTemplate.Rooms.Message.LeaveOutMuted do
  @moduledoc """
  Leaves out messages from anyone the signed-in reader muted, and those a muted
  agent wrote for its person; a visitor or an agent sees every message.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  alias AshTemplate.Actors.Human

  @impl true
  def prepare(query, _opts, %{actor: %Human{human_account_id: reader}}) do
    Ash.Query.filter(
      query,
      not exists(author_mutes, muter_account_id == ^reader) and
        not exists(agent_mutes, muter_account_id == ^reader) and
        not exists(via_agent_mutes, muter_account_id == ^reader)
    )
  end

  def prepare(query, _opts, _context), do: query
end

defmodule AshTemplate.Rooms.Message.ByAuthorKind do
  @moduledoc """
  Keeps only people's messages (`author_kind: :person`, including those a paired
  agent wrote for its person) or only those agents posted as themselves
  (`:agent`), as each message's `author_kind` says; without it, every message.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    case Ash.Query.get_argument(query, :author_kind) do
      nil -> query
      :person -> Ash.Query.filter(query, is_nil(agent_id))
      :agent -> Ash.Query.filter(query, not is_nil(agent_id))
    end
  end
end

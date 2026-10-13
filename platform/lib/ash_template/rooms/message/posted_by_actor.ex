defmodule AshTemplate.Rooms.Message.PostedByActor do
  @moduledoc """
  Keeps only messages the actor posted, as `SetAuthor` recorded them: a person's
  own, a paired agent's for its person, or an unpaired agent's as itself.
  """

  use Ash.Resource.Preparation

  require Ash.Query

  alias AshTemplate.Actors.{Agent, Human}

  @impl true
  def prepare(query, _opts, %{actor: %Human{human_account_id: account}}),
    do: Ash.Query.filter(query, human_account_id == ^account)

  def prepare(query, _opts, %{actor: %Agent{pairing: :active} = agent}) do
    Ash.Query.filter(
      query,
      human_account_id == ^agent.human_account_id and via_agent_id == ^agent.agent_id
    )
  end

  def prepare(query, _opts, %{actor: %Agent{agent_id: agent}}),
    do: Ash.Query.filter(query, agent_id == ^agent)

  def prepare(query, _opts, _context), do: Ash.Query.filter(query, false)
end

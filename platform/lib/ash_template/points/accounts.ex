defmodule AshTemplate.Points.Accounts do
  @moduledoc "Verified account lookups supplied to the shared Points package."
  @behaviour RegentPoints.Accounts

  require Ash.Query

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.System

  @impl true
  def human(id), do: Accounts.points_account!(id, actor: %System{})

  @impl true
  def agent_names(_id, []), do: {:ok, %{}}

  def agent_names(id, ids) do
    query = Ash.Query.filter(RegentAgents.PairedAgent, id in ^ids)

    # Reads as the account's own person, so the agents policy shows only that person's agents.
    with {:ok, account} <- Accounts.points_account(id, actor: %System{}),
         person = %RegentAgents.Person{privy_user_id: account.privy_user_id},
         {:ok, agents} <- RegentAgents.list_my_agents(query: query, actor: person) do
      {:ok, Map.new(agents, &{&1.id, &1.name})}
    end
  end
end

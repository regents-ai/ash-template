defmodule AshTemplateWeb.PanelAgents do
  @moduledoc """
  The agents paired with the person's account (`RegentAgents`), in the side panel
  on every page, in the shared agents list (`Regent.Account.agents`). Pairing is
  shared by every Regent site, so an agent paired on another one is listed too.
  The Account page's list (`AshTemplateWeb.AgentsPanel`) opens one and unpairs it.

  The parent passes `account` (the signed-in account), its `session_lease` as
  `lease` and `id`, and sends `agents_changed: true` when an agent pairs, checks
  in or is unpaired anywhere.
  """
  use AshTemplateWeb, :live_component

  alias AshTemplateWeb.{AgentsPanel, Live.Session}
  alias RegentAgents.Person

  @impl true
  def mount(socket), do: {:ok, Session.check_component_lease(socket, &take_account/2)}

  @impl true
  def update(%{agents_changed: true}, socket), do: {:ok, read_agents(socket)}

  def update(%{account: account, id: id, lease: lease}, socket),
    do: {:ok, socket |> assign(id: id, lease: lease) |> take_account(account) |> read_agents()}

  # The account as the page gave it, or as it reads now before each event
  # (`Session.check_component_lease/2`).
  defp take_account(socket, account),
    do: assign(socket, person: %Person{privy_user_id: account.privy_user_id})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Regent.Account.agents id={@id} agents={AgentsPanel.rows(@agents, @now)} />
    </div>
    """
  end

  defp read_agents(socket) do
    agents =
      case RegentAgents.list_my_agents(actor: socket.assigns.person) do
        {:ok, agents} -> agents
        {:error, _error} -> :unavailable
      end

    assign(socket, agents: agents, now: DateTime.utc_now())
  end
end

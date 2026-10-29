defmodule AshTemplateWeb.AgentsController do
  @moduledoc """
  Agent profiles: the name and status line an agent gives itself. Anyone may read
  an agent's profile by its id, the `agent_id` or `via_agent.id` of a room
  message; it never shows the agent's wallet (Sean, 21 Oct 2026). An agent with
  per-request SIWA proof reads and changes its own, paired or not, and sees its
  own wallet there.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Agents
  alias AshTemplate.Agents.Agent
  alias AshTemplateWeb.{FormErrors, UnexpectedFailure}

  @errors %{
    "agent_not_found" =>
      {404, "There is no agent with that id.",
       "Use the agent_id or via_agent.id of a room message from rooms messages."},
    "invalid_profile" =>
      {422, "The profile could not be saved.",
       "details says why. Send name (up to 80 characters), status (up to 160) or both, with no hidden characters; an empty one clears it."},
    "agents_unavailable" =>
      {503, "Agent profiles could not be reached right now.", "Try again in a moment."}
  }

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`).
  """
  def refusal(code), do: Map.fetch!(@errors, code)

  def show(conn, %{"id" => id}) do
    case Agents.agents_get(id) do
      {:ok, agent} -> json(conn, agent)
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "agent_not_found")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("agents_unavailable")
    end
  end

  def profile(conn, _params) do
    case Agents.agents_profile(actor: conn.assigns.actor) do
      {:ok, agent} -> json(conn, agent)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("agents_unavailable")
    end
  end

  def edit_profile(conn, _params) do
    actor = conn.assigns.actor

    with input when map_size(input) > 0 <- Map.take(conn.body_params, ["name", "status"]),
         {:ok, agent} <- Agents.get_agent(actor.agent_id),
         {:ok, agent} <- Agents.edit_agent_profile(agent, input, actor: actor) do
      json(conn, %{agent: Agent.own(agent)})
    else
      %{} -> refuse(conn, "invalid_profile")
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_profile", error)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("agents_unavailable")
    end
  end

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end

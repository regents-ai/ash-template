defmodule AshTemplateWeb.AgentsController do
  @moduledoc """
  Agent profiles: the name and status line an agent gives itself. Anyone may read
  an agent's profile by its id, the `agent_id` or `via_agent.id` of a room
  message; it never shows the agent's wallet (Sean, 21 Oct 2026). An agent with
  per-request SIWA proof reads and changes its own, paired or not, and sees its
  own wallet there.

  Each route runs the agents action its browser tool and hosted MCP tool run,
  and this table holds the words of every agent profile refusal, on each surface.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Agents
  alias AshTemplate.Agents.Refused
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

  @doc """
  The refusal `{code, extra}` an agent's change to its own profile answers for
  input it cannot take: the profile's own refusal, or `invalid_profile` with
  `details`. The route and the hosted MCP server answer the same.
  """
  @spec input_refusal(Ash.Error.Invalid.t()) :: {String.t(), map()}
  def input_refusal(%Ash.Error.Invalid{errors: errors} = error) do
    case Enum.find(errors, &match?(%Refused{}, &1)) do
      nil -> {"invalid_profile", details(error)}
      refused -> answer(refused)
    end
  end

  @doc "An agents action's own refusal as `{code, extra}`: what the code alone leaves out."
  @spec answer(Refused.t()) :: {String.t(), map()}
  def answer(%Refused{code: code, error: %Ash.Error.Invalid{} = error}),
    do: {code, details(error)}

  def answer(%Refused{code: code}), do: {code, %{}}

  defp details(error), do: %{details: FormErrors.details(error)}

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

  # A field the change does not take is refused, not left out.
  def edit_profile(conn, _params) do
    case Agents.agents_edit_profile(conn.body_params, actor: conn.assigns.actor) do
      {:ok, agent} ->
        json(conn, agent)

      {:error, %Ash.Error.Invalid{} = error} ->
        {code, extra} = input_refusal(error)
        refuse(conn, code, extra)

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("agents_unavailable")
    end
  end

  defp refuse(conn, code, extra \\ %{}) do
    {status, message, hint} = Map.fetch!(@errors, code)

    conn
    |> put_status(status)
    |> json(%{error: Map.merge(%{code: code, message: message, hint: hint}, extra)})
  end
end

defmodule AshTemplateWeb.VisitLog.ProductEvents do
  @moduledoc """
  The product events (`AshTemplate.ProductEvents`) an HTTP answer shows, read
  as the answer leaves (`AshTemplateWeb.VisitLog.Events`), so none of the code
  that did the work changes:

  - `account_created` and `signed_in`: the sign-in exchange answered that it
    bound the browser to an account (`x-ash-session-changed: true`).
  - `agent_paired`: `POST /api/agents/v1/pair` answered `201`.
  - `agent_acted`: a signed agent request succeeded after an Ash create, update
    or destroy ran as the agent.

  Any failure here is logged and dropped: a `:telemetry` handler that raises is
  detached, and the visit lines would stop with it.
  """

  require Logger

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.{Agent, System}
  alias AshTemplate.ProductEvents
  alias AshTemplateWeb.{PrivySessionController, VisitLog}
  alias RegentAgents.{Authority, Harness}

  # Set in a request's process when an Ash write ran as an agent.
  @agent_wrote {__MODULE__, :agent_wrote}
  @sign_in ["auth", "privy", "session"]
  @pair ["api", "agents", "v1", "pair"]

  @doc "Notes that an Ash create, update or destroy ran as `actor`, when it is an agent."
  def agent_wrote(%Agent{}), do: Process.put(@agent_wrote, true)
  def agent_wrote(_actor), do: :ok

  @doc "Writes the product events the answer `conn` shows; `route` is its route."
  def observe(conn, route) do
    wrote = Process.delete(@agent_wrote) == true
    if conn.status in 200..299, do: answered(conn, route, wrote)
    :ok
  rescue
    error -> unobserved(error.__struct__)
  catch
    :exit, _reason -> unobserved(:exit)
  end

  defp answered(%Plug.Conn{method: "POST", path_info: @sign_in} = conn, _route, _wrote),
    do: signed_in(conn)

  defp answered(%Plug.Conn{method: "POST", path_info: @pair, status: 201} = conn, _route, _wrote),
    do: paired(conn)

  defp answered(%Plug.Conn{path_info: ["api" | _]} = conn, route, true),
    do: acted(conn.assigns[:actor], "#{conn.method} #{route}")

  defp answered(_conn, _route, _wrote), do: :ok

  # The answer's own session names the account it was bound to.
  defp signed_in(conn) do
    if Plug.Conn.get_resp_header(conn, "x-ash-session-changed") == ["true"] do
      account = PrivySessionController.enforce_authority(conn).assigns.current_human_account
      if account, do: ProductEvents.signed_in(account, VisitLog.first_touch(conn))
    end
  end

  # The pairing has committed, so the agent's wallet now names its person.
  defp paired(%Plug.Conn{assigns: %{regent_agent: %RegentAgents.Agent{wallet: wallet}}} = conn) do
    with {:ok, %{privy_user_id: person}} <- Authority.resolve(AshTemplate.Repo, wallet),
         {:ok, account} <- Accounts.get_by_privy_did(person, actor: %System{}) do
      ProductEvents.record(:agent_paired, account, %{kind: harness(conn.body_params)})
    end
  end

  defp paired(_conn), do: :ok

  defp acted(%Agent{} = agent, kind), do: ProductEvents.record(:agent_acted, agent, %{kind: kind})
  defp acted(_actor, _kind), do: :ok

  defp harness(%{"harness" => sent}) do
    case Harness.match(sent) do
      {:ok, harness} -> Atom.to_string(harness)
      :error -> nil
    end
  end

  defp harness(_params), do: nil

  defp unobserved(kind),
    do: Logger.warning("The product events of an answer weren't read: #{inspect(kind)}")
end

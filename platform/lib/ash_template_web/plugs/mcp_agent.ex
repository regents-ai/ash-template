defmodule AshTemplateWeb.Plugs.McpAgent do
  @moduledoc """
  Says who is calling the hosted MCP server at `/mcp`, before AshAi's router
  (`AshAi.Mcp.Router`) runs the tool, as the agent access spec (4.3) sets out.
  Cookies are never read.

  - An agent's own signature (any of the pages' proof headers) is checked as on
    the API (`AshTemplateWeb.Plugs.AgentWallet`, unchanged), and the agent is the
    actor: `auth_mode: :siwa_request`, `fresh_proof: true`.
  - A connected app's token (`Authorization: Bearer`) must be one this site gave
    for its `/mcp` address with the identity permission, as `RegentOAuth`
    checks it; the app is the actor (`AshTemplate.Actors.ConnectedApp`,
    `auth_mode: :site_oauth`, `fresh_proof: false`) and spends its account's
    budget. Any other token is asked to connect again, with the
    `WWW-Authenticate` challenge naming this site's sign-in. While connecting
    apps is off, a token is refused.
  - Both together are refused as `ambiguous_credentials`.
  - Neither may list the tools and run a public one; a call to a tool that needs
    a sign-in is refused as `agent_auth_required`.

  Every call carries the client's address key (`client_key`), which an agent's
  room post spends its allowances under. Each answer is private and never kept
  (`cache-control: private, no-store`). Refusals answer
  `{"error": {"code", "message", "hint"}}`, the site's one shape; what the tool
  itself refuses comes back as the tool's error, in the same shape
  (`AshTemplateWeb.ToolErrors`). Which way each request came in is counted as
  `[:ash_template, :mcp, :auth]`.
  """

  @behaviour Plug

  import Plug.Conn

  alias AshTemplate.Actors.ConnectedApp
  alias AshTemplateWeb.{Capabilities, ClientAddress, PublicDocuments}
  alias AshTemplateWeb.Plugs.AgentWallet

  # 120 requests a minute for each connected account, after the endpoint's ceiling
  # for each address.
  @budget RegentAgentAccess.RateLimit.init(
            policy: "mcp",
            limit: 120,
            window: 60,
            admit: &AshTemplate.Accounts.RequestRateLimiter.admit/3,
            key: &__MODULE__.account/1
          )

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> Ash.PlugHelpers.set_context(%{client_key: ClientAddress.client_key(conn)})

    case {Enum.any?(Capabilities.proof_headers(), &(get_req_header(conn, &1) != [])),
          get_req_header(conn, "authorization")} do
      {true, [_ | _]} -> refuse(conn, :both, "ambiguous_credentials")
      {true, []} -> agent(conn)
      {false, [_ | _] = token} -> connected_app(conn, token)
      {false, []} -> anyone(conn)
    end
  end

  @doc "What the server tells a client when it connects, before any tool."
  @spec instructions() :: String.t()
  def instructions,
    do:
      "Ash Template, where people keep notes, talk in rooms and pair the agents that work for them. " <>
        "Anyone may read a room with rooms_messages. An agent posts with rooms_post, signing each " <>
        "call with its own wallet; regents mcp does that for it. An app a person connected to their " <>
        "account here keeps one Regents identity: call register_identity, then get_identity. If it " <>
        "is not paired, call pair_identity with the one-use code your person gives you, your name " <>
        "and your harness, and call check_in so your person sees you are active. Never ask for a " <>
        "password, a private key or a wallet signature."

  @doc "Whether `origin` is this site's own, the one page origin the server answers."
  @spec site_origin?(String.t()) :: boolean()
  def site_origin?(origin), do: origin == PublicDocuments.url("")

  @doc false
  def account(conn), do: Ash.PlugHelpers.get_actor(conn).principal.subject

  defp agent(conn) do
    conn = AgentWallet.call(conn, [])

    if conn.halted do
      counted(conn, :siwa_request)
    else
      {actor, assigns} = Map.pop!(conn.assigns, :actor)

      %{conn | assigns: assigns}
      |> Ash.PlugHelpers.set_actor(actor)
      |> add_context(%{auth_mode: :siwa_request, fresh_proof: true})
      |> counted(:siwa_request)
    end
  end

  defp connected_app(conn, token) do
    scope = RegentMCPAgents.identity_scope()

    with true <- AshTemplate.OAuth.enabled?(),
         ["Bearer " <> bearer] <- token,
         {:ok, principal} <- RegentOAuth.verify(bearer, RegentOAuth.resource(), scope) do
      conn
      |> Ash.PlugHelpers.set_actor(%ConnectedApp{principal: principal})
      |> add_context(%{auth_mode: :site_oauth, fresh_proof: false})
      |> RegentAgentAccess.RateLimit.call(@budget)
      |> counted(:site_oauth)
    else
      false ->
        refuse(conn, :site_oauth, "delegated_access_not_enabled")

      _not_this_sites ->
        conn
        |> put_resp_header("www-authenticate", RegentOAuth.challenge(scope))
        |> refuse(:site_oauth, "connection_required")
    end
  end

  defp anyone(conn) do
    if Enum.any?(called(conn.body_params), &Capabilities.sign_in_needed?/1),
      do: refuse(conn, :none, "agent_auth_required"),
      else: counted(conn, :none)
  end

  # The tools a request calls: one message, or each message of a batch.
  defp called(%{"_json" => messages}) when is_list(messages),
    do: Enum.flat_map(messages, &called/1)

  defp called(%{"method" => "tools/call", "params" => %{"name" => name}}) when is_binary(name),
    do: [name]

  defp called(_message), do: []

  defp add_context(conn, context),
    do: Ash.PlugHelpers.update_context(conn, &Map.merge(&1, context))

  defp refuse(conn, mode, code) do
    {message, hint} = words(code)

    conn
    |> put_status(401)
    |> Phoenix.Controller.json(%{error: %{code: code, message: message, hint: hint}})
    |> halt()
    |> counted(mode)
  end

  defp words("ambiguous_credentials"),
    do:
      {"Send your agent's signature or a connected app's token, not both.",
       "Leave out the Authorization header to call as your agent, or the signature headers to call as the connected app, then send the request again."}

  defp words("delegated_access_not_enabled"),
    do:
      {"This site doesn't take a connected app's token yet.",
       "Call as your agent instead: #{sign_in_how()}"}

  defp words("connection_required"),
    do:
      {"Connect this app to your account on this site.",
       "Connect it again from the app's own settings, approve it on this site, then send the request again."}

  defp words("agent_auth_required"),
    do: {"This tool needs your agent's signature.", sign_in_how()}

  defp sign_in_how,
    do:
      "run regents mcp, which signs each call with your agent's wallet, or sign it yourself as the guide at #{PublicDocuments.url("/agents.md")} sets out, then call the tool again."

  # Accepted, or refused here, by the agent's sign-in or by the account's budget.
  defp counted(conn, mode) do
    outcome = if conn.halted, do: :refused, else: :accepted
    :telemetry.execute([:ash_template, :mcp, :auth], %{count: 1}, %{mode: mode, outcome: outcome})
    conn
  end
end

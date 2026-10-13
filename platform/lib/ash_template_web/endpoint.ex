defmodule AshTemplateWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ash_template

  # A connected mount reads the cookie the socket handshake carried, so the
  # transport must decode it with the same options the request plug runs with.
  @session_options {Application, :fetch_env!, [:ash_template, :session_options]}

  # A stylesheet, an icon or an image may be opened directly, and the browser
  # then reads it as a page. These say what a page from this address may do,
  # which is nothing.
  @static_headers %{
    "content-security-policy" => "default-src 'none'; frame-ancestors 'none'",
    "x-content-type-options" => "nosniff",
    "x-frame-options" => "DENY",
    "referrer-policy" => "no-referrer"
  }

  # Chrome's WebMCP origin trial, issued to https://template.regents.sh and valid
  # until 30 Mar 2027. The token is public; Chrome ignores it on any other host.
  @webmcp_origin_trial "Anjl5/zD6iF9O/lRuJbhbnuaTCH/1+x83KMsVLt4KEl5eI5kKV0yqXI+xOxti+nzSe7uQ0UUj1Ot3fi/WVyczwEAAABTeyJvcmlnaW4iOiJodHRwczovL3RlbXBsYXRlLnJlZ2VudHMuc2g6NDQzIiwiZmVhdHVyZSI6IldlYk1DUCIsImV4cGlyeSI6MTgwNjM2NDgwMH0="

  @rate_limit RegentAgentAccess.RateLimit.init(
                policy: "default",
                limit: 120,
                window: 60,
                admit: &AshTemplate.Accounts.RequestRateLimiter.admit/3,
                key: &AshTemplateWeb.ClientAddress.key/1
              )
  # Pairing also has its own small budget, since each try spends a guess at a code.
  @pair_rate_limit RegentAgentAccess.RateLimit.init(
                     policy: "pair",
                     limit: 10,
                     window: 60,
                     admit: &AshTemplate.Accounts.RequestRateLimiter.admit/3,
                     key: &AshTemplateWeb.ClientAddress.key/1
                   )

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :uri, session: @session_options]],
    longpoll: [connect_info: [:peer_data, :uri, session: @session_options]]

  plug AshTemplateWeb.Plugs.CanonicalHost
  plug AshTemplateWeb.Plugs.ContractHeaders

  plug Plug.Static,
    at: "/",
    from: :ash_template,
    gzip: not code_reloading?,
    only: AshTemplateWeb.static_paths(),
    only_matching: AshTemplateWeb.digested_static_prefixes(),
    raise_on_missing_only: code_reloading?,
    headers: @static_headers

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Every answer, including the Markdown and refusals the next plug gives before
  # the router, lets browser agents use the tools this site's pages register and
  # carries the origin-trial token, so Chrome knows it before reading `tools`.
  plug :allow_page_tools

  # One budget per client address, shared by the health check and every /api path,
  # answered or not; pairing counts against its own budget too. Every answer says
  # what is left of each; past one, 429 with Retry-After.
  plug :limit_rate

  # Before the parsers, so a body they reject on an /api path is answered in
  # JSON like every other API error.
  plug RegentAgentAccess.Plug,
    documents: &AshTemplateWeb.PublicDocuments.document/1,
    guide: "/llms.txt"

  # The largest body the site takes is a sign-in request of a few kilobytes;
  # anything past a megabyte is refused before it is read.
  plug AshTemplateWeb.Plugs.Parsers,
    body_reader: {AshTemplateWeb.SignedBodyReader, :read_body, []},
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    length: 1_000_000,
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug :runtime_session
  plug AshTemplateWeb.Router

  defp allow_page_tools(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header("permissions-policy", "tools=(self)")
    |> Plug.Conn.put_resp_header("origin-trial", @webmcp_origin_trial)
  end

  defp limit_rate(%Plug.Conn{path_info: ["healthz"]} = conn, _opts),
    do: RegentAgentAccess.RateLimit.call(conn, @rate_limit)

  defp limit_rate(
         %Plug.Conn{method: "POST", path_info: ["api", "agents", "v1", "pair"]} = conn,
         _opts
       ) do
    conn = RegentAgentAccess.RateLimit.call(conn, @rate_limit)
    if conn.halted, do: conn, else: RegentAgentAccess.RateLimit.call(conn, @pair_rate_limit)
  end

  defp limit_rate(%Plug.Conn{path_info: ["api" | _]} = conn, _opts),
    do: RegentAgentAccess.RateLimit.call(conn, @rate_limit)

  defp limit_rate(%Plug.Conn{path_info: ["tools" | _]} = conn, _opts),
    do: RegentAgentAccess.RateLimit.call(conn, @rate_limit)

  defp limit_rate(conn, _opts), do: conn

  # Production sets the cookie's `secure` flag in runtime.exs, after this module compiles.
  defp runtime_session(conn, _opts) do
    options = Application.fetch_env!(:ash_template, :session_options)
    Plug.Session.call(conn, Plug.Session.init(options))
  end
end

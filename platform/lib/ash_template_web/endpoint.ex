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

  @doc "The headers every file and public document is sent with; it is never a page."
  def static_headers, do: @static_headers

  # The largest signed body is a note: 10,000 characters of text, as JSON.
  @signed_body_limit 65_536

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
  # Page loads have a generous budget of their own: each renders the page and
  # runs its reads, and one address loading pages faster than ten a second is not
  # a person. Moving between pages uses the open live connection and costs
  # nothing here, files are answered above it, and 600 a minute still lets about a
  # hundred people behind one shared address (an office, a phone carrier) load a
  # page every ten seconds each.
  @page_rate_limit RegentAgentAccess.RateLimit.init(
                     policy: "page",
                     limit: 600,
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

  # fullsweep_after: 0 has each page's connection give back what it used to send
  # the page: 1.67 MB down to 0.09 MB a page where it was measured
  # (ash-frontend, references/public-figures.md).
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [:peer_data, :uri, session: @session_options],
      fullsweep_after: 0,
      # The largest message a page sends is a note being written: a title and
      # body of 10,120 characters as the browser counts them, up to 9 bytes each
      # once form-encoded, about 91 KB. No page takes a file.
      max_frame_size: 262_144
    ]

  plug AshTemplateWeb.Plugs.CanonicalHost

  # esbuild names every file in assets/js/chunks after its contents, so a
  # changed file has a new name: a browser keeps them for a year without asking
  # again. Each page's own entry script is cached by its digest.
  plug Plug.Static,
    at: "/assets/js/chunks",
    from: {:ash_template, "priv/static/assets/js/chunks"},
    gzip: not code_reloading?,
    cache_control_for_etags: "public, max-age=31536000, immutable",
    headers: @static_headers

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
  # Which visit, and which kind of caller, each line of this request belongs to.
  plug AshTemplateWeb.VisitLog
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Every answer, including the Markdown and refusals the next plug gives before
  # the router and pages that do not exist, runs under the strict policy unless its
  # route sets a wider one. It lets browser agents use the tools this site's pages
  # register and carries the origin-trial token, so Chrome knows it before reading
  # `tools`.
  plug :secure_every_answer

  # One budget per client address, shared by the health check, the browser's visit
  # reports and every /api path, answered or not; pairing counts against its own
  # budget too, the MCP address has its own, and so does every other page or
  # document loaded. Every answer says what is left of each; past one, 429 with
  # Retry-After. The live socket's connect never reaches this plug, and behind
  # Fly its peer is the proxy, so open pages are counted per address as they join
  # (`AshTemplateWeb.Live.OpenPages`).
  plug :limit_rate

  # Before the parsers, so a body they reject on an /api path or the MCP address
  # is answered in JSON like every other API error.
  plug RegentAgentAccess.Plug,
    documents: &AshTemplateWeb.PublicDocuments.document/1,
    guide: "/llms.txt",
    json_prefixes: ["api", "mcp"]

  # After the error format is chosen, so a slash address is answered as any
  # address that names nothing.
  plug AshTemplateWeb.Plugs.NoTrailingSlash

  # A body an agent signs stops at 64 KB (`read_body/2`). The rest, a connected
  # app's registration or token, a sign-in, a visit report, are a few KB; anything
  # past 256 KB is refused before it is read.
  plug AshTemplateWeb.Plugs.Parsers,
    body_reader: {__MODULE__, :read_body, []},
    parsers: [Plug.Parsers.URLENCODED, Plug.Parsers.JSON],
    pass: ["*/*"],
    length: 262_144,
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug :runtime_session
  plug AshTemplateWeb.Router

  # The policy is built by ContentSecurityPolicy; Sobelow cannot evaluate its value.
  # sobelow_skip ["Config.CSP"]
  defp secure_every_answer(conn, _opts) do
    Phoenix.Controller.put_secure_browser_headers(conn, %{
      "content-security-policy" => AshTemplateWeb.ContentSecurityPolicy.reading(),
      "permissions-policy" => "tools=(self)",
      "origin-trial" => @webmcp_origin_trial
    })
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

  defp limit_rate(%Plug.Conn{method: "POST", path_info: ["visit-log"]} = conn, _opts),
    do: RegentAgentAccess.RateLimit.call(conn, @rate_limit)

  defp limit_rate(%Plug.Conn{path_info: ["api" | _]} = conn, _opts),
    do: RegentAgentAccess.RateLimit.call(conn, @rate_limit)

  defp limit_rate(%Plug.Conn{path_info: ["mcp" | _]} = conn, _opts),
    do: AshTemplateWeb.Plugs.McpAgent.limit_address(conn)

  defp limit_rate(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD"],
    do: RegentAgentAccess.RateLimit.call(conn, @page_rate_limit)

  defp limit_rate(conn, _opts), do: conn

  # Production sets the cookie's `secure` flag in runtime.exs, after this module compiles.
  defp runtime_session(conn, _opts) do
    options = Application.fetch_env!(:ash_template, :session_options)
    Plug.Session.call(conn, Plug.Session.init(options))
  end

  # Keeps the exact bytes of every body the API and the hosted MCP server take, so
  # the sign-in service can check them against the request's signature
  # (AshTemplateWeb.Plugs.AgentWallet, RegentAgents.HTTP): any of them may come
  # from an agent. The pages' own form bodies are read as before.
  def read_body(%Plug.Conn{method: method, path_info: ["api" | _rest]} = conn, opts)
      when method in ["POST", "PATCH"],
      do: Siwa.AgentAuthPlug.read_body(conn, opts, @signed_body_limit)

  def read_body(%Plug.Conn{method: "POST", path_info: ["mcp"]} = conn, opts),
    do: Siwa.AgentAuthPlug.read_body(conn, opts, @signed_body_limit)

  def read_body(conn, opts), do: RegentIdentity.BodyReader.read_body(conn, opts)
end

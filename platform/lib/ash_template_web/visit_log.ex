defmodule AshTemplateWeb.VisitLog do
  @moduledoc """
  One log line for each thing a person or agent did, what the site did about it
  and how it ended, so a visit can be replayed from the lines
  (docs/logging-replay-plan.md).

  Every line carries the same few fields and nothing else: in production the
  JSON formatter writes only the `visit`, `actor`, `surface`, `request_id` and
  `event` metadata (config/runtime.exs), and `record/4` keeps only an event's
  name, where it happened, its outcome and how long it took. Free text never
  reaches a line: names, routes and tool names come from the site's own code or
  from a short header checked against a pattern, and anything else is written as
  `other`.

  - `visit`: a random id for one browser visit, kept in the `_visit` cookie until
    the browser closes and sent by the page's own scripts in `x-regent-visit`
    when they send no cookies. It is not tied to the account. Calls from outside
    a page have none.
  - `actor`: `person:` or `agent:` and a one-way code for the account or agent,
    or `anonymous`. The code cannot be turned back into the account.
  - `surface`: `page`, `webmcp`, `cli`, `agent_http`, `mcp` or `job`. The page's
    tools say `x-regent-client: webmcp/<tool>`; Regents CLI says
    `regents-cli/<version> <command>`. An API call that names neither but
    carries a visit is the page's own script, so it is `page`. A call to the
    hosted MCP server at `/mcp` is `mcp`.

  A `tool.call` line also names its `client`: `webmcp`, `regents-cli/<version>`,
  another program's `<name>/<version>` as its `x-regent-client` gave them,
  `other` for a header that gives neither, or `none`.

  The events themselves come from `AshTemplateWeb.VisitLog.Events`; the browser
  adds the few only it can see through `AshTemplateWeb.VisitLogController`.

  Visit lines have a handler of their own (`handler/2`), sized for a crowd acting
  at once, and the default handler leaves them to it (`default_filter/0`).

  Two kinds of line show where people come from and where they stop, the same
  on every site:

  - `arrival`: the first page of a visit, once its page has connected (so a
    crawler that runs no script writes none), by route and where the visit came
    from: a name from `sources/0` (from `utm_source`, else the referring site),
    `site` for this site, `other_site` for any other, or `direct`. The referring
    address itself is never written.
  - `step`: one of `steps/0`, the shared journey from first look to a paired
    agent and the site's value action, with the agent's harness where there is
    one.

  `steps/0` is the product-event vocabulary, the same fixed list on every site;
  its names never change. Every step but `sign_in_opened` (a press only the
  browser sees) is written by the server once the change it names has
  succeeded: `signed_in`, `pairing_code_shown`, `agent_paired`, and the value
  names of `values/0` (`value/2`), one per site, to which each site maps its own
  value action.

  A browser that sends Global Privacy Control (`Sec-GPC: 1`) starts no visit: it
  gets no `_visit` cookie, none of its requests or pages carries a `visit`, and it
  writes no `arrival` or `step` line. Its other lines are written without a
  visit, like calls from outside a page, so nothing groups them into one visit.
  """

  @behaviour Plug

  require Logger

  import Plug.Conn

  @cookie "_visit"
  # Set in each request's and page's process when its browser sent Global Privacy Control.
  @gpc {__MODULE__, :gpc}
  @visit ~r/\A[A-Za-z0-9_-]{22}\z/
  @webmcp ~r/\Awebmcp\/([a-z][a-z0-9_]{0,63})\z/
  @cli ~r/\Aregents-cli\/([0-9A-Za-z.+-]{1,32}) ([a-z0-9][a-z0-9 _-]{0,63})\z/
  @program ~r/\A([a-z][a-z0-9._-]{0,31}\/[0-9][0-9A-Za-z.+-]{0,31})(?: |\z)/
  @where ~r/\A[A-Za-z0-9_.:\/@* -]{1,120}\z/
  @outcome ~r/\A[a-z0-9_]{1,48}\z/
  @names ~w(request tool.call page press action job outgoing page.error tool.unsent press.unsent arrival step)
  # The domain `record` gives its lines; Elixir puts `:elixir` before every domain.
  @domain [:elixir, :visit]
  # A visit line is a request, press or change, so the lines follow real traffic: the
  # handler keeps 2,000 a second and 2,000 waiting to be written (Erlang's defaults are
  # 500 and 200), the crowd the site is built for. Past 10 waiting, each process waits
  # for its line to be written (Erlang's default), and past 4,000 the waiting lines are
  # let go, so a flood still cannot exhaust the machine.
  @limits %{
    burst_limit_max_count: 2_000,
    burst_limit_window_time: 1_000,
    drop_mode_qlen: 2_000,
    flush_qlen: 4_000
  }
  # The value action of each site, one name a site, so every site writes the same
  # list: the template's note, Keyfleet's contribution, Patchbay's fix, Techtree's
  # eval and Autolaunch's launch.
  @values ~w(note_created contribution_made fix_succeeded eval_completed launch_confirmed)
  @steps ~w(sign_in_opened signed_in pairing_code_shown agent_paired) ++ @values
  # A program's call to the site, by the first part of its whole path.
  @calls ~w(api mcp)
  # Where a visit came from, by the referring site's address or `utm_source`.
  @sources %{
    "chatgpt.com" => "chatgpt",
    "chat.openai.com" => "chatgpt",
    "perplexity.ai" => "perplexity",
    "claude.ai" => "claude",
    "gemini.google.com" => "gemini",
    "copilot.microsoft.com" => "copilot",
    "google.com" => "google",
    "bing.com" => "bing",
    "duckduckgo.com" => "duckduckgo",
    "x.com" => "x",
    "twitter.com" => "x",
    "t.co" => "x",
    "linkedin.com" => "linkedin",
    "lnkd.in" => "linkedin",
    "github.com" => "github",
    "news.ycombinator.com" => "hackernews",
    "reddit.com" => "reddit"
  }

  @doc "The metadata a production line carries (config/runtime.exs)."
  def fields, do: [:request_id, :visit, :actor, :surface, :event]

  @doc """
  The handler that writes visit lines, and only them, to `config`'s destination
  with `formatter` (config/runtime.exs), with the limits above.
  """
  def handler(config, formatter) do
    {:handler, :visits, :logger_std_h,
     %{
       config: Map.merge(config, @limits),
       formatter: formatter,
       filter_default: :stop,
       filters: [
         remote_gl: {&:logger_filters.remote_gl/2, :stop},
         visits: {&:logger_filters.domain/2, {:log, :sub, @domain}}
       ]
     }}
  end

  @doc "The default handler's filter that leaves visit lines to `handler/2`."
  def default_filter, do: {&:logger_filters.domain/2, {:stop, :sub, @domain}}

  @doc "The named steps of the shared journey: the product-event vocabulary."
  def steps, do: @steps

  @doc "The steps that are a site's value action; each site writes only its own."
  def values, do: @values

  @doc "The names an arrival can give for where it came from, besides `site`, `other_site` and `direct`."
  def sources, do: @sources |> Map.values() |> Enum.uniq()

  @doc """
  Writes one `step` line: one of `steps/0` that is not a value step (those go
  through `value/2`), with the agent's harness where there is one. Nothing is
  written for a browser that sends Global Privacy Control.
  """
  def step(name, harness \\ nil) when name in @steps and name not in @values do
    unless Process.get(@gpc), do: record("step", name, harness)
    :ok
  end

  @doc """
  Writes one value step (`values/0`): the site's value action has succeeded for
  the account `actor` acts for. The line names that account, as a `person:`
  code, whether the person or their agent acted, and its outcome says which:
  `person` or `agent`. Its visit and surface are the request's or page's own.
  Nothing is written for a browser that sends Global Privacy Control.

  It is called from the action's own process once its transaction has committed
  (`AshTemplate.Journey.Value`), so it answers `:ok` whatever happens, a name
  outside `values/0` included: a line is never a reason for the action to fail.
  """
  def value(name, actor) do
    cond do
      name not in @values -> Logger.warning("#{inspect(name)} is not a value step")
      Process.get(@gpc) -> :ok
      true -> write(event("step", name, by(actor), nil), actor: account(actor))
    end

    :ok
  rescue
    error -> Logger.warning("A value step was not written: #{inspect(error.__struct__)}")
  catch
    _kind, _reason -> :ok
  end

  defp by(%AshTemplate.Actors.Agent{}), do: "agent"
  defp by(_person), do: "person"

  # The account an action was for: a person's own, or the one their agent works for.
  defp account(%AshTemplate.Actors.Agent{human_account_id: id}) when not is_nil(id),
    do: "person:" <> code(id)

  defp account(actor), do: actor(actor)

  @doc "Writes one event line (`event/4`); its message is its name, where and outcome."
  def record(name, where, outcome \\ nil, ms \\ nil, client \\ nil),
    do: write(event(name, where, outcome, ms, client), [])

  # `metadata` sets a field for this line alone, such as the account a value step names.
  defp write(event, metadata) do
    message = Enum.join([event.name, event.where | List.wrap(event[:outcome])], " ")
    # `domain` sends the line to its own handler and is never printed, so it is not one
    # of the formatter's metadata keys.
    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.info(fn -> {message, [event: event] ++ metadata} end, domain: [:visit])
  end

  @doc """
  One event. `where` and `outcome` that do not fit their pattern are written as
  `other`; `ms` is a whole number of milliseconds or left out; `client` is one of
  `caller/1`'s answers or left out.
  """
  def event(name, where, outcome, ms, client \\ nil) when name in @names do
    %{
      name: name,
      where: fit(where, @where),
      outcome: outcome && fit(outcome, @outcome),
      ms: ms,
      client: client
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp fit(value, pattern) when is_binary(value),
    do: if(Regex.match?(pattern, value), do: value, else: "other")

  defp fit(value, pattern) when is_atom(value), do: fit(Atom.to_string(value), pattern)
  defp fit(_value, _pattern), do: "other"

  @doc "The one-way code for who acted: an account, a signed-in agent, or nobody."
  def actor(%AshTemplate.Actors.Agent{agent_id: id}), do: "agent:" <> code(id)
  def actor(%AshTemplate.Accounts.HumanAccount{id: id}), do: "person:" <> code(id)
  def actor(%AshTemplate.Actors.Human{human_account_id: id}), do: "person:" <> code(id)
  def actor(%AshTemplate.AccessContext{principal: {:human, account}}), do: actor(account)
  def actor(_nobody), do: "anonymous"

  defp code(id) do
    :crypto.mac(:hmac, :sha256, key(), to_string(id))
    |> binary_part(0, 8)
    |> Base.encode16(case: :lower)
  end

  # Derived from the endpoint's secret, so the codes cannot be recomputed from
  # account ids without it, and stay the same across machines and releases.
  defp key do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        key =
          AshTemplateWeb.Endpoint.config(:secret_key_base)
          |> Plug.Crypto.KeyGenerator.generate("visit log actor", length: 32)

        :persistent_term.put(__MODULE__, key)
        key

      key ->
        key
    end
  end

  @doc "Where a request or page lands, as its route (`/rooms/:room`), never its own path."
  def route(router, method, path, host) do
    case Phoenix.Router.route_info(router, method, path, host) do
      %{route: route} -> route
      :error -> "unmatched"
    end
  end

  @doc "Short module names: `RoomsLive`, not `AshTemplateWeb.RoomsLive`."
  def short(module) when is_atom(module), do: module |> inspect() |> short()

  def short(name) when is_binary(name),
    do:
      name
      |> String.replace_prefix("AshTemplateWeb.", "")
      |> String.replace_prefix("AshTemplate.", "")

  # Plug: every request through the endpoint, before the router.

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    gpc = gpc?(conn)
    {surface, client} = surface(conn)
    {conn, visit} = if gpc, do: {forget(conn), nil}, else: visit(conn, surface)
    # Only a browser sends Global Privacy Control, so its API calls are its page's own.
    surface = if surface == "agent_http" and (visit || gpc), do: "page", else: surface
    Logger.metadata(visit: visit, surface: surface)
    Process.put(@gpc, gpc)

    conn
    |> assign(:visit, visit)
    |> assign(:gpc, gpc)
    |> put_private(:visit_log_client, client)
    |> put_private(:visit_log_caller, caller(conn, surface))
  end

  # The program that made an API or MCP call, as its `x-regent-client` names it.
  defp caller(conn, surface) do
    case {call?(conn), surface, get_req_header(conn, "x-regent-client")} do
      {false, _surface, _sent} -> nil
      {true, "webmcp", _sent} -> "webmcp"
      {true, _surface, []} -> "none"
      {true, _surface, [sent | _]} -> program(sent)
    end
  end

  @doc """
  Whether a request is a program's call to the site, `/api` or the hosted MCP
  server at `/mcp`, by its whole path: a plug the router forwards to, such as
  `RegentAgents.HTTP` under `/api/agents/v1`, sees only the rest of it.
  """
  def call?(conn), do: match?([part | _] when part in @calls, conn.script_name ++ conn.path_info)

  defp program(sent) do
    case Regex.run(@program, sent) do
      [_all, program] -> program
      nil -> "other"
    end
  end

  # A page keeps its cookie's visit, and a page opened without one starts a visit.
  # An API call takes the visit its page's script sent, in the header when it
  # sends no cookies, or in the cookie when it does.
  defp visit(conn, "page") do
    case conn.cookies[@cookie] do
      visit when is_binary(visit) ->
        if Regex.match?(@visit, visit), do: {conn, visit}, else: start(conn)

      nil ->
        if page?(conn), do: start(conn), else: {conn, nil}
    end
  end

  defp visit(conn, _surface) do
    sent = get_req_header(conn, "x-regent-visit") ++ List.wrap(conn.cookies[@cookie])
    {conn, Enum.find(sent, &Regex.match?(@visit, &1))}
  end

  defp start(conn) do
    visit = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn =
      conn
      |> put_resp_cookie(@cookie, visit,
        http_only: true,
        same_site: "Lax",
        secure: conn.scheme == :https
      )
      |> assign(:arrival, arrival(conn))

    {conn, visit}
  end

  @doc "Whether the browser sent Global Privacy Control: no visit, cookie, `arrival` or `step` line for it."
  def gpc?(conn), do: get_req_header(conn, "sec-gpc") == ["1"]

  # A browser that now asks not to be tracked loses the visit it was given before.
  defp forget(%Plug.Conn{cookies: %{@cookie => _visit}} = conn),
    do: delete_resp_cookie(conn, @cookie)

  defp forget(conn), do: conn

  @doc "Where a visit that starts with this request came from (see the moduledoc)."
  def arrival(conn) do
    conn = fetch_query_params(conn)

    with nil <- source(conn.query_params["utm_source"]),
         [referrer | _] <- get_req_header(conn, "referer"),
         %URI{host: host} when is_binary(host) <- URI.parse(referrer) do
      cond do
        host == conn.host -> "site"
        source = source(host) -> source
        true -> "other_site"
      end
    else
      source when is_binary(source) -> source
      _no_referrer -> "direct"
    end
  end

  # A site's address, with or without `www.` or another part in front, or a
  # source's own name (`utm_source=chatgpt`).
  defp source(name) when is_binary(name) do
    name = name |> String.downcase() |> String.replace_prefix("www.", "")

    @sources[name] ||
      Enum.find_value(@sources, fn {site, source} ->
        if String.ends_with?(name, "." <> site), do: source
      end) ||
      if(name in sources(), do: name)
  end

  defp source(_nothing), do: nil

  # Only a browser opening a page asks for HTML; health checks and API calls don't.
  defp page?(conn),
    do: conn |> get_req_header("accept") |> Enum.any?(&String.contains?(&1, "text/html"))

  defp surface(%Plug.Conn{path_info: ["mcp" | _]}), do: {"mcp", nil}

  defp surface(%Plug.Conn{path_info: ["api" | _]} = conn) do
    client = conn |> get_req_header("x-regent-client") |> List.first("")

    cond do
      match = Regex.run(@webmcp, client) -> {"webmcp", Enum.at(match, 1)}
      match = Regex.run(@cli, client) -> {"cli", "#{Enum.at(match, 2)}@#{Enum.at(match, 1)}"}
      true -> {"agent_http", nil}
    end
  end

  defp surface(_conn), do: {"page", nil}

  @doc "The tool or command the caller named in `x-regent-client`, if any."
  def client(conn), do: conn.private[:visit_log_client]

  @doc "The program that made an API call (see the moduledoc); nil for anything else."
  def caller(conn), do: conn.private[:visit_log_caller]

  # on_mount, for every LiveView (AshTemplateWeb.live_view/0). The connected page
  # runs in its own process, so it takes the visit its first render passed on
  # (AshTemplateWeb.Live.Session.render_context/1). A page the router opened writes
  # a `page` line when it opens and each time its address changes, whether or not
  # it handles params itself; a view drawn inside another page is part of that page.
  # The first page of a visit writes its `arrival` line first. The page keeps the
  # session it was drawn with across moves to other pages and reconnects, so only
  # the first connection of the page as loaded writes it: a reconnect counts
  # `_mounts` above 0, and a move to another page names the page it left.
  def on_mount(:default, _params, session, socket) do
    visit = session["visit"]

    Logger.metadata(visit: visit, surface: "page", actor: actor(socket.assigns[:access_context]))
    Process.put(@gpc, session["gpc"] == true)

    socket =
      Phoenix.Component.assign(socket, visit: visit, arrival: first_arrival(session, socket))

    if socket.router,
      do: {:cont, Phoenix.LiveView.attach_hook(socket, :visit_log_page, :handle_params, &page/3)},
      else: {:cont, socket}
  end

  defp first_arrival(session, socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         %{"_mounts" => 0} = params <- Phoenix.LiveView.get_connect_params(socket),
         nil <- params["_live_referer"] do
      session["arrival"]
    else
      _not_the_first -> nil
    end
  end

  defp page(_params, uri, socket) do
    if Phoenix.LiveView.connected?(socket) do
      %URI{path: path, host: host} = URI.parse(uri)
      Logger.metadata(actor: actor(socket.assigns[:access_context]))
      route = route(socket.router, "GET", path, host)
      if arrival = socket.assigns.arrival, do: record("arrival", route, arrival)
      record("page", route)
      {:cont, Phoenix.Component.assign(socket, :arrival, nil)}
    else
      {:cont, socket}
    end
  end
end

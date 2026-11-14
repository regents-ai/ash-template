defmodule AshTemplateWeb.LiveCrashesTest do
  # A live page that fails keeps the browser's session, and what the page holds,
  # out of the log and out of the saved error (`AshTemplateWeb.LiveCrashes`). On
  # 13 Nov one such crash on a Regent site printed the whole session, its form
  # token and live socket id included, into the lines Fly and Sentinel keep.
  use ExUnit.Case, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint AshTemplateWeb.Endpoint

  defmodule RaisingLive do
    use AshTemplateWeb, :live_view

    @impl true
    def mount(_params, _session, socket) do
      if connected?(socket), do: raise("the page failed as it connected"), else: {:ok, socket}
    end

    @impl true
    def render(assigns), do: ~H"<p>page</p>"
  end

  defmodule UnmatchedLive do
    use AshTemplateWeb, :live_view

    # Once connected it takes only a session naming a room, so the stack's first
    # line carries the session it was given.
    @impl true
    def mount(_params, _session, %{transport_pid: nil} = socket), do: {:ok, socket}
    def mount(_params, %{"room" => _room}, socket), do: {:ok, socket}

    @impl true
    def render(assigns), do: ~H"<p>page</p>"
  end

  defmodule PressLive do
    use AshTemplateWeb, :live_view

    @impl true
    def mount(_params, _session, socket),
      do: {:ok, assign(socket, held: %{secret: "held-marker-51e0"})}

    # A press without `known` matches no head, so the stack's first line carries
    # the socket and every assign on it.
    @impl true
    def handle_event("press", %{"known" => _known}, socket), do: {:noreply, socket}

    @impl true
    def render(assigns) do
      ~H"""
      <button phx-click="press">Press</button>
      """
    end
  end

  @session %{
    "_csrf_token" => "form-token-marker-7c1e",
    "live_socket_id" => "session_authority:socket-marker-4d2b",
    "session_lineage" => "lineage-marker-9a3f",
    "session_generation" => 0
  }

  # Every page is drawn with its address key (`AshTemplateWeb.Live.OpenPages`).
  @page %{"client_key" => "live-crashes-test"}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  for {failure, view, exception} <- [
        {"raises", RaisingLive, RuntimeError},
        {"matches none of its mount heads", UnmatchedLive, FunctionClauseError}
      ] do
    @view view
    @exception exception

    test "a page that #{failure} as it connects names the failure and none of the session" do
      log =
        capture_log(fn -> catch_exit(live_isolated(with_session(), @view, session: @page)) end)

      assert_named_without(log, @view, @exception, [
        @session["_csrf_token"],
        @session["live_socket_id"],
        @session["session_lineage"]
      ])
    end
  end

  test "a page whose press matches no head names the failure and none of what it holds" do
    {:ok, view, _html} = live_isolated(with_session(), PressLive, session: @page)

    # The open page is linked to this test, which outlives it.
    Process.flag(:trap_exit, true)
    log = capture_log(fn -> catch_exit(render_click(view, "press", %{})) end)

    assert_named_without(log, PressLive, FunctionClauseError, [
      "held-marker-51e0",
      @session["session_lineage"]
    ])
  end

  # The socket connects with the decoded cookie session, as a browser's does.
  defp with_session do
    build_conn()
    |> Plug.Conn.put_private(:live_view_connect_info, %{session: @session})
    |> put_connect_params(%{"_csrf_token" => @session["_csrf_token"]})
  end

  defp assert_named_without(log, view, exception, markers) do
    # The saved errors are ErrorTracker's own tables, not Ash records.
    saved =
      AshTemplate.Repo.all(
        from(error in ErrorTracker.Error,
          join: occurrence in assoc(error, :occurrences),
          where: fragment("?->>'live_view.view'", occurrence.context) == ^to_string(view),
          select: {error, occurrence}
        )
      )

    assert log =~ inspect(exception)
    assert [{%{kind: kind}, _occurrence}] = saved
    assert kind == to_string(exception)

    for marker <- markers do
      refute log =~ marker
      refute inspect(saved, limit: :infinity, printable_limit: :infinity) =~ marker
    end
  end
end

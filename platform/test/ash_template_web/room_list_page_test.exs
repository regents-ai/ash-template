defmodule AshTemplateWeb.RoomListPageTest do
  # The rooms page's list in the sidebar: the 50 most recently active, with More
  # for the next page. A room beyond them opens like any other, joins the end of
  # the list marked as the open room, and moves to its place when More reaches
  # it. A post anywhere moves its room to the top of every open page from what
  # the notice carries, with no query on any of them.
  #
  # A shell page cannot be mounted connected in a mix test, so `Host` holds the
  # room page as the shell does: the sidebar the list is put in, and each notice
  # on the rooms topic handed on to it (`AshTemplateWeb.ShellLive`).
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.{Accounts, Repo, Rooms}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Rooms.Room

  @endpoint AshTemplateWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    alias AshTemplate.Rooms
    alias AshTemplate.Rooms.Room
    alias AshTemplateWeb.RoomsLive

    @impl true
    def mount(_params, %{"room" => slug}, socket) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(AshTemplate.PubSub, Room.topic())
      {:ok, room} = Rooms.get_room(slug)
      {:ok, assign(socket, :room, room)}
    end

    @impl true
    def handle_info(%{topic: "public:rooms", event: event, payload: room}, socket) do
      send_update(RoomsLive, id: "rooms", room_change: {event, room})
      {:noreply, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="shell-sidebar-page"></div>
      <.live_component
        module={RoomsLive}
        id="rooms"
        lease={nil}
        account={nil}
        room={@room}
        client_key="room-list-page-test"
      />
      """
    end
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    n = :erlang.unique_integer([:positive])
    now = DateTime.utc_now()

    for k <- 1..55 do
      seed_room("page-#{n}-#{k}", DateTime.add(now, -k, :minute))
    end

    %{n: n, beyond: seed_room("beyond-#{n}", DateTime.add(now, -2, :day))}
  end

  test "a room beyond the first 50 opens, at the end of the list, marked", %{beyond: beyond} do
    html =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> get("/rooms/#{beyond.slug}")
      |> html_response(200)

    shown = marked(Enum.take(by_activity(), 50) ++ [beyond.slug], beyond.slug)
    assert links(html) == shown

    {:ok, view, _html} = live_isolated(build_conn(), Host, session: %{"room" => beyond.slug})
    assert links(view) == shown
  end

  test "More shows the next page, and the open room moves to its place", %{beyond: beyond} do
    {:ok, view, _html} = live_isolated(build_conn(), Host, session: %{"room" => beyond.slug})
    assert more?(view)

    view |> with_target("#rooms-page") |> render_click("more_rooms", %{})

    assert links(view) == marked(by_activity(), beyond.slug)
    refute more?(view)
  end

  test "a post moves its room to the top of an open page with no query there", %{
    n: n,
    beyond: beyond
  } do
    {:ok, view, _html} = live_isolated(build_conn(), Host, session: %{"room" => beyond.slug})
    person = person(n)
    queries = queries_by(view.pid)
    middle = Enum.at(by_activity(), 30)

    post!(person, middle)
    settle(view)
    assert [{^middle, nil} | _] = links(view)
    assert links(view) == marked(Enum.take(by_activity(), 50) ++ [beyond.slug], beyond.slug)

    # The room already on top stays where it is.
    post!(person, middle)
    settle(view)
    assert links(view) == marked(Enum.take(by_activity(), 50) ++ [beyond.slug], beyond.slug)

    # The open room, shown at the end, moves from there to the top.
    post!(person, beyond.slug)
    settle(view)
    assert [{_open, "page"} | _] = links(view)
    assert links(view) == marked(Enum.take(by_activity(), 51), beyond.slug)

    assert queries.() == 0

    # The count sees the page's own reads: More reads the next page.
    view |> with_target("#rooms-page") |> render_click("more_rooms", %{})
    assert queries.() > 0
  end

  # The list as it should read: each room's slug, the open one marked.
  defp marked(slugs, open), do: Enum.map(slugs, &{&1, if(&1 == open, do: "page")})

  # The room page has handled the notice and the update it handed on.
  defp settle(view) do
    :sys.get_state(view.pid)
    :sys.get_state(view.pid)
  end

  # Each link in the list: its room's slug and whether it is marked as the open room.
  defp links(%Phoenix.LiveViewTest.View{} = view),
    do: view |> element("#rooms-sidebar") |> render() |> links()

  defp links(html) do
    html
    |> template_content()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#rooms-list a")
    |> Enum.map(fn link ->
      ["/rooms/" <> slug] = LazyHTML.attribute(link, "href")
      {slug, link |> LazyHTML.attribute("aria-current") |> List.first()}
    end)
  end

  # A portal's content sits in a template, which a selector does not reach.
  defp template_content(html) do
    [content] = Regex.run(~r/<template id="rooms-sidebar"[^>]*>(.*?)<\/template>/s, html, capture: :all_but_first)
    content
  end

  defp more?(view) do
    view
    |> element("#rooms-sidebar")
    |> render()
    |> template_content()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("button[phx-click=more_rooms]")
    |> Enum.count() == 1
  end

  # Every room's slug, the most recently active first, read straight from the table.
  defp by_activity do
    %{rows: rows} =
      Repo.query!("SELECT slug FROM #{Repo.default_prefix()}.rooms ORDER BY last_active_at DESC, slug DESC")

    List.flatten(rows)
  end

  # How many queries `pid` has made since asked.
  defp queries_by(pid) do
    test = self()
    handler = "room-list-page-test-#{:erlang.unique_integer()}"

    :telemetry.attach(
      handler,
      [:ash_template, :repo, :query],
      fn _event, _measure, _meta, _ -> if self() == pid, do: send(test, :queried) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    fn -> drain(0) end
  end

  defp drain(n) do
    receive do
      :queried -> drain(n + 1)
    after
      0 -> n
    end
  end

  defp seed_room(slug, at),
    do: Ash.Seed.seed!(Room, %{slug: slug, name: slug, topic: "Paging", inserted_at: at, last_active_at: at})

  defp person(n) do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!("did:privy:room-list-page-#{n}", wallet, [wallet], actor: %System{})
  end

  defp post!(account, room) do
    Rooms.post_message!(%{room: room, body: "Moving up"},
      actor: Human.for_account(account),
      context: %{client_key: account.id}
    )
  end
end

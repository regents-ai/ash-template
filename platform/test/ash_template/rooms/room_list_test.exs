defmodule AshTemplate.Rooms.RoomListTest do
  # The list of rooms (Sean, 12 Nov 2026: limit the room list to 50). Every
  # reader reads it a page at a time, at most 50, the most recently active
  # first, and pages onward by the last room's cursor; agents page it as they
  # page notes. A post moves its room to the top in its own transaction, never
  # back, and tells every open page all the list draws of the room. The
  # migration that added the time gave each room the later of when it was
  # started and its newest saved message.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.{Accounts, Repo, Rooms}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Rooms.{Message, Room}

  Code.require_file("priv/repo/migrations/20261112230808_rooms_last_active.exs")
  alias AshTemplate.Repo.Migrations.RoomsLastActive

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    %{n: :erlang.unique_integer([:positive])}
  end

  test "the list reads at most 50 rooms, the most recently active first, and pages onward", %{n: n} do
    seed_rooms(n, 120)

    first_fifty = Enum.take(by_activity(), 50)
    assert {:ok, %Ash.Page.Keyset{results: first, more?: true}} = Rooms.list_rooms()
    assert Enum.map(first, & &1.slug) == first_fifty
    assert {:ok, %{results: asked_for_more}} = Rooms.list_rooms(page: [limit: 500])
    assert Enum.map(asked_for_more, & &1.slug) == first_fifty

    pages = pages([])
    assert Enum.all?(pages, &(Enum.count(&1.results) in 1..50))
    assert Enum.flat_map(pages, fn page -> Enum.map(page.results, & &1.slug) end) == by_activity()
  end

  test "a post moves its room to the top and tells every open page what the list draws", %{n: n} do
    quiet = n |> seed_rooms(60) |> List.last()
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Room.topic())

    message = post!(person(n), quiet.slug)

    assert_receive %{event: "active", payload: payload}
    assert payload == %{slug: quiet.slug, name: quiet.name, topic: quiet.topic}
    assert {:ok, %{results: [top | _]}} = Rooms.list_rooms()
    assert {top.slug, top.last_active_at} == {quiet.slug, message.inserted_at}

    # A post that committed after a later one never moves its room back.
    earlier = DateTime.add(message.inserted_at, -1, :second)
    assert {:ok, room} = Rooms.mark_room_active(quiet.slug, earlier, actor: %System{})
    assert room.last_active_at == message.inserted_at

    # Only a post moves a room; no person or agent does it themselves.
    assert {:error, %Ash.Error.Forbidden{}} =
             Rooms.mark_room_active(quiet.slug, DateTime.utc_now(), actor: Human.for_account(person(n + 1)))
  end

  test "agents page the list as they page notes", %{n: n} do
    seed_rooms(n, 70)

    first = rooms_json("/api/v1/rooms", 200)
    assert Enum.map(first["rooms"], & &1["slug"]) == Enum.take(by_activity(), 50)
    assert Enum.all?(first["rooms"], &(Map.keys(&1) == ["name", "slug", "topic"]))
    assert %{"has_more" => true, "next_cursor" => cursor} = first["pagination"]

    rest = onward(cursor)
    assert Enum.map(first["rooms"] ++ rest, & &1["slug"]) == by_activity()

    assert %{"error" => %{"code" => "invalid_cursor"}} = rooms_json("/api/v1/rooms?after=nope", 422)
    assert %{"error" => %{"code" => "invalid_cursor"}} = rooms_json("/api/v1/rooms?after[]=x", 422)
  end

  test "the migration gives each room the later of its start and its newest saved message", %{n: n} do
    author = person(n)
    started = ~U[2026-11-01 00:00:00.000000Z]
    quiet = seed_room("fill-quiet-#{n}", started)
    busy = seed_room("fill-busy-#{n}", started)
    moved_in = seed_room("fill-moved-in-#{n}", started)

    seed_message(busy, author, ~U[2026-11-05 10:00:00.000000Z])
    seed_message(busy, author, ~U[2026-11-07 09:30:00.123456Z])
    seed_message(moved_in, author, ~U[2026-10-01 12:00:00.000000Z])

    prefix = Repo.default_prefix()
    Repo.query!("UPDATE #{prefix}.rooms SET last_active_at = '2000-01-01'")
    Repo.query!(RoomsLastActive.fill(prefix))

    assert active_at(quiet) == started
    assert active_at(busy) == ~U[2026-11-07 09:30:00.123456Z]
    assert active_at(moved_in) == started
  end

  # Every page of the list, first to last.
  defp pages(page) do
    {:ok, result} = Rooms.list_rooms(page: page)
    if result.more?, do: [result | pages(after: List.last(result.results).__metadata__.keyset)], else: [result]
  end

  defp onward(cursor) do
    page = rooms_json("/api/v1/rooms?after=" <> URI.encode_www_form(cursor), 200)

    case page["pagination"] do
      %{"has_more" => true, "next_cursor" => next} -> page["rooms"] ++ onward(next)
      %{"has_more" => false, "next_cursor" => nil} -> page["rooms"]
    end
  end

  defp rooms_json(path, status) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> get(path)
    |> json_response(status)
  end

  # Every room's slug, the most recently active first, read straight from the table.
  defp by_activity do
    %{rows: rows} =
      Repo.query!("SELECT slug FROM #{Repo.default_prefix()}.rooms ORDER BY last_active_at DESC, slug DESC")

    List.flatten(rows)
  end

  defp active_at(room) do
    {:ok, %Room{last_active_at: at}} = Rooms.get_room(room.slug)
    at
  end

  # Rooms last active a minute apart, the most recently active first.
  defp seed_rooms(n, count) do
    now = DateTime.utc_now()
    for k <- 1..count, do: seed_room("list-#{n}-#{k}", DateTime.add(now, -k, :minute))
  end

  defp seed_room(slug, at),
    do: Ash.Seed.seed!(Room, %{slug: slug, name: slug, topic: "Paging", inserted_at: at, last_active_at: at})

  defp seed_message(room, author, at) do
    Ash.Seed.seed!(Message, %{
      room: room.slug,
      body: "Earlier",
      human_account_id: author.id,
      author_wallet: author.wallet_address,
      inserted_at: at
    })
  end

  defp person(n) do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!("did:privy:room-list-#{n}", wallet, [wallet], actor: %System{})
  end

  defp post!(account, room) do
    Rooms.post_message!(%{room: room, body: "Moving up"},
      actor: Human.for_account(account),
      context: %{client_key: account.id}
    )
  end
end

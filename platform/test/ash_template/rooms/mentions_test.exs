defmodule AshTemplate.Rooms.MentionsTest do
  # A mention reaches the person it names by the name the room shows them by: the
  # name they chose, else their ENS name, else the short wallet a person with no
  # name shows by. Each name a person has posted under in a room is kept for it
  # (`AshTemplate.Rooms.Poster`), filled for the messages already posted when
  # posters began, so a mention reaches exactly the people the room's messages
  # named before.
  use ExUnit.Case, async: false

  require Ash.Query

  alias AshTemplate.{Accounts, Activity, Agents, Repo, Rooms}
  alias AshTemplate.Activity.Notification
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Rooms.{Like, Message, Room}

  Code.require_file("priv/repo/migrations/20261112192414_rooms_like_counts_and_posters.exs")
  alias AshTemplate.Repo.Migrations.RoomsLikeCountsAndPosters

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "someone with no name is told when a message mentions their short wallet" do
    nameless = person("mention-nameless")
    writer = person("mention-writer")
    post!(nameless, "Hello")

    short = RegentFormat.short_address(nameless.wallet_address)
    post!(writer, "Welcome @#{String.upcase(short)}")

    assert [%{path: "/rooms/general"}] = notifications(nameless)
    assert [] = notifications(writer)
  end

  test "over a room's history, a mention reaches exactly whom the room's messages named" do
    n = :erlang.unique_integer([:positive])
    room = seed_room("mentions-#{n}")
    other_room = seed_room("mentions-other-#{n}")

    [named, ens, both, nameless, renamed, elsewhere, liker, writer] =
      Enum.map(~w(named ens both nameless renamed elsewhere liker writer), &person("history-#{&1}-#{n}"))

    agent = Agents.sign_in_agent!(wallet(), actor: %System{})

    # Messages posted before posters were kept, so none of them recorded one.
    history!(room, named, author_name: "Ada")
    history!(room, ens, author_ens_name: "bob.eth")
    history!(room, both, author_name: "Eve", author_ens_name: "evelyn.eth")
    history!(room, nameless, [])
    history!(room, renamed, author_name: "Dora")
    history!(room, renamed, author_name: "Dorothy")
    history!(other_room, elsewhere, author_name: "Frank")

    liked = history!(room, writer, author_name: "Wren")
    for liker <- [named, liker], do: Ash.Seed.seed!(Like, %{message_id: liked.id, liker_id: liker.id, room: room})

    Ash.Seed.seed!(Message, %{room: room, body: "As myself", agent_id: agent.id, author_name: "Smith"})

    Enum.each(RoomsLikeCountsAndPosters.fill(Repo.default_prefix()), &Repo.query!/1)

    assert %{like_count: 2, like_version: 0} = Ash.get!(Message, liked.id, authorize?: false)

    short = "0x" <> String.slice(nameless.wallet_address, 2, 4) <> ".." <> String.slice(nameless.wallet_address, -4, 4)

    bodies = [
      "Hello @ada and @BOB.ETH",
      "Thanks @evelyn.eth, and @Eve",
      "Over to you @#{String.upcase(short)}",
      "Still @dora to me",
      "Or @Dorothy now",
      "Ask @Smith or @frank",
      "Nobody named here",
      "Just an @ on its own"
    ]

    for body <- bodies do
      expected = MapSet.delete(named_by_messages(room, body), writer.id)
      post!(writer, body, room)
      assert notified(body) == expected, body
    end

    # The names reached between them every person who posted in the room.
    reached = bodies |> Enum.map(&notified/1) |> Enum.reduce(&MapSet.union/2)
    assert reached == MapSet.new([named.id, ens.id, both.id, nameless.id, renamed.id])
  end

  # Whom a message in `room` with `body` named before posters were kept: every
  # person whose message in the room was posted under a name the body holds
  # after an "@", in any case, by the query mentions ran over the room's messages.
  defp named_by_messages(room, body) do
    Message
    |> Ash.Query.filter(
      room == ^room and not is_nil(human_account_id) and
        fragment(
          "strpos(lower(?), '@' || lower(coalesce(?, ?, '0x' || substr(?, 3, 4) || '..' || right(?, 4)))) > 0",
          ^body,
          author_name,
          author_ens_name,
          author_wallet,
          author_wallet
        )
    )
    |> Ash.Query.select([:human_account_id])
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.human_account_id)
  end

  defp notified(body) do
    Notification
    |> Ash.Query.filter(body == ^body)
    |> Ash.read!(authorize?: false)
    |> MapSet.new(& &1.human_account_id)
  end

  defp seed_room(slug), do: Ash.Seed.seed!(Room, %{slug: slug, name: slug, topic: "History"}).slug

  defp history!(room, account, names) do
    Ash.Seed.seed!(
      Message,
      Map.merge(
        %{room: room, body: "Earlier", human_account_id: account.id, author_wallet: account.wallet_address},
        Map.new(names)
      )
    )
  end

  defp person(id) do
    wallet = wallet()
    Accounts.register_verified!("did:privy:" <> id, wallet, [wallet], actor: %System{})
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

  defp post!(account, body, room \\ "general") do
    Rooms.post_message!(%{room: room, body: body},
      actor: Human.for_account(account),
      context: %{client_key: account.id}
    )
  end

  defp notifications(account) do
    {:ok, page} = Activity.list_my_notifications(actor: Human.for_account(account), page: [limit: 50])
    page.results
  end
end

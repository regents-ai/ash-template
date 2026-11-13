defmodule AshTemplate.TextSearchTest do
  # Every text search (room messages across rooms, rooms by name, a person's
  # notes) matches in any case, takes `%`, `_` and `\` in the words as
  # themselves, finds nothing without a query under three letters, and keeps
  # its order and limit. Each runs as ILIKE on a trigram index.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Notes, Rooms}
  alias AshTemplate.Actors.{Human, System}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    %{person: person(), word: word()}
  end

  test "a search finds its words in any case", %{person: person, word: word} do
    message = post(person, "Saw a #{word} today")
    note = write(person, "Trip #{word}", "Nothing else")
    noted = write(person, "Groceries", "Pick up #{word} food")
    room = start(person, "#{word} Club")

    for text <- [String.upcase(word), String.downcase(word)] do
      assert ids(Rooms.search_messages!(text, actor: person)) == ids([message])
      assert ids(Notes.search_my_notes!(text, actor: person)) == ids([noted, note])
      assert slugs(Rooms.search_rooms!(text)) == slugs([room])
    end
  end

  test "%, _ and \\ in the words are matched as written", %{person: person, word: word} do
    wildcards = post(person, "#{word} 5%_off")
    post(person, "#{word} 5xyoff")
    backslash = post(person, "#{word} c:\\temp")
    post(person, "#{word} c:temp")

    assert ids(Rooms.search_messages!("5%_off", actor: person)) == ids([wildcards])
    assert ids(Rooms.search_messages!("c:\\temp", actor: person)) == ids([backslash])

    note = write(person, "#{word} 50%_done", "")
    write(person, "#{word} 50xydone", "")
    assert ids(Notes.search_my_notes!("50%_done", actor: person)) == ids([note])

    room = start(person, "#{word} 7%_up")
    start(person, "#{word} 7xyup")
    assert slugs(Rooms.search_rooms!("7%_up")) == slugs([room])
  end

  test "under three letters finds nothing and runs no query", %{person: person, word: word} do
    post(person, "Saw a #{word} today")
    write(person, "Trip #{word}", "")
    start(person, "#{word} Club")

    for text <- [String.slice(word, 0, 2), " #{String.slice(word, 0, 2)} ", "a"] do
      assert {[], []} = statements(fn -> Rooms.search_messages!(text, actor: person) end)
      assert {[], []} = statements(fn -> Notes.search_my_notes!(text, actor: person) end)
      assert {[], []} = statements(fn -> Rooms.search_rooms!(text) end)
    end

    three = String.slice(word, 0, 3)
    assert {[_ | _], [_ | _]} = statements(fn -> Rooms.search_messages!(three, actor: person) end)
    assert {[_ | _], [_ | _]} = statements(fn -> Notes.search_my_notes!(three, actor: person) end)
    assert {[_ | _], [_ | _]} = statements(fn -> Rooms.search_rooms!(three) end)
  end

  test "results stay newest first for messages and notes, oldest first for rooms, five at most",
       %{person: person, word: word} do
    messages = for n <- 1..6, do: post(person, "#{word} message #{n}")
    notes = for n <- 1..6, do: write(person, "#{word} note #{n}", "")
    rooms = for n <- 1..6, do: start(if(n <= 3, do: person, else: person()), "#{word} #{n}")

    assert ids(Rooms.search_messages!(word, actor: person), :ordered) ==
             messages |> Enum.reverse() |> Enum.take(5) |> ids(:ordered)

    assert ids(Notes.search_my_notes!(word, actor: person), :ordered) ==
             notes |> Enum.reverse() |> Enum.take(5) |> ids(:ordered)

    assert Enum.map(Rooms.search_rooms!(word), & &1.slug) ==
             rooms |> Enum.take(5) |> Enum.map(& &1.slug)
  end

  # What `fun` answers, and each statement the repo ran in this process meanwhile.
  defp statements(fun) do
    handler = "text-search-test-#{:erlang.unique_integer()}"
    test = self()

    :telemetry.attach(
      handler,
      [:ash_template, :repo, :query],
      fn _event, _measure, meta, _config ->
        if self() == test, do: send(test, {:statement, meta.query})
      end,
      nil
    )

    result = fun.()
    :telemetry.detach(handler)
    {result, collect([])}
  end

  defp collect(sql) do
    receive do
      {:statement, query} -> collect([query | sql])
    after
      0 -> Enum.reverse(sql)
    end
  end

  defp post(person, body) do
    Rooms.post_message!(%{room: "general", body: body},
      actor: person,
      context: %{client_key: "text-search-" <> Ecto.UUID.generate()}
    )
  end

  defp write(person, title, body),
    do: Notes.create_note!(%{title: title, body: body}, actor: person)

  defp start(person, name) do
    Rooms.create_room!(%{name: name, topic: "Search"},
      actor: person,
      context: %{client_key: "text-search-" <> Ecto.UUID.generate()}
    )
  end

  defp ids(records, order \\ :sorted)
  defp ids(records, :sorted), do: records |> Enum.map(& &1.id) |> Enum.sort()
  defp ids(records, :ordered), do: Enum.map(records, & &1.id)

  defp slugs(rooms), do: rooms |> Enum.map(& &1.slug) |> Enum.sort()

  # Letters only, mixed case, found in no other test's text.
  defp word do
    letters = for _ <- 1..10, into: "", do: <<Enum.random(?a..?z)>>
    "Qx" <> letters
  end

  defp person do
    did = "did:privy:text-search-" <> Ecto.UUID.generate()
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    Human.for_account(account)
  end
end

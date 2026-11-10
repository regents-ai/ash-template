defmodule AshTemplate.Rooms.ModerationTest do
  # The site's operator reads every report and removes a reported message with a
  # reason that is kept (`AshTemplate.Rooms.Moderation`). Nobody else can do
  # either: a person reads only their own reports and removes no one else's
  # message.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Rooms}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Rooms.{Message, Moderation, Removal}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    # A room and an author of their own: other tests leave messages in general,
    # and a person starts only a few rooms a day.
    n = :erlang.unique_integer([:positive])
    author = person("did:privy:moderation-author-#{n}", "a")
    room = Rooms.create_room!(%{name: "Moderation #{n}", topic: "Reports"}, author)

    %{
      author: author,
      room: room.slug,
      first: person("did:privy:moderation-first", "b"),
      second: person("did:privy:moderation-second", "c")
    }
  end

  test "the operator sees each reported message once, most reported first, with its reasons counted",
       %{author: author, room: room, first: first, second: second} do
    spam = Rooms.post_message!(%{room: room, body: "Buy now"}, author)
    rude = Rooms.post_message!(%{room: room, body: "Rude words"}, author)
    _fine = Rooms.post_message!(%{room: room, body: "Hello"}, author)

    Rooms.report_message!(spam.id, :spam, first)
    Rooms.report_message!(spam.id, :steers_agents, second)
    Rooms.report_message!(rude.id, :abuse, first)

    {:ok, reported} = Moderation.reported()
    ours = Enum.filter(reported, &(&1.message.room == room))

    assert [
             %{message: %{id: spam_id}, reports: 2, reasons: %{spam: 1, steers_agents: 1}},
             %{message: %{id: rude_id}, reports: 1, reasons: %{abuse: 1}}
           ] = ours

    assert {spam_id, rude_id} == {spam.id, rude.id}
  end

  test "removing a message takes it, its likes and its reports, tells the room's open pages and keeps the reason",
       %{author: author, room: room, first: first, second: second} do
    spam = Rooms.post_message!(%{room: room, body: "Buy now"}, author)
    Rooms.report_message!(spam.id, :spam, first)
    Rooms.like_message!(spam.id, second)
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Message.topic(room))

    assert {:ok, %{id: removed}} = Moderation.remove(spam.id, "Spam, reported by two people")
    assert removed == spam.id

    assert {:ok, nil} = Rooms.get_message(spam.id, first)
    assert {:ok, reported} = Moderation.reported()
    refute Enum.any?(reported, &(&1.message.id == spam.id))

    # Open pages of the room drop it as they drop any deleted message.
    id = spam.id
    assert_receive %{event: "destroy", payload: %{id: ^id, room: ^room}}

    # The record holds who wrote it and why it went, never its words.
    assert [%Removal{} = record] =
             Removal |> Ash.read!(actor: %System{}) |> Enum.filter(&(&1.message_id == spam.id))

    assert record.room == room
    assert record.reason == "Spam, reported by two people"
    assert record.human_account_id == author[:actor].human_account_id
    refute Map.has_key?(Map.from_struct(record), :body)

    # A second removal, or an id that never named a message, changes nothing.
    assert {:error, :not_found} = Moderation.remove(spam.id, "Again")
    assert {:error, :not_found} = Moderation.remove("not-a-uuid", "Nothing there")
  end

  test "only the operator reads everyone's reports or removes someone else's message",
       %{author: author, room: room, first: first, second: second} do
    said = Rooms.post_message!(%{room: room, body: "Hello"}, author)
    Rooms.report_message!(said.id, :other, first)

    # A person, the author included, is refused both; the message stays.
    for someone <- [author, first, second] do
      assert {:error, %Ash.Error.Forbidden{}} = Rooms.list_reports(someone)

      assert {:error, %Ash.Error.Forbidden{}} =
               Rooms.remove_message(said, "I would like it gone", someone)
    end

    assert {:error, %Ash.Error.Forbidden{}} = Removal |> Ash.read(first)
    assert {:ok, %{id: _}} = Rooms.get_message(said.id, first)

    # A removal with no reason is refused, and the message stays.
    assert {:error, %Ash.Error.Invalid{}} = Rooms.remove_message(said, "", actor: %System{})
    assert {:ok, %{id: _}} = Rooms.get_message(said.id, first)
  end

  # Options to act as a new person, from their own address.
  defp person(did, letter) do
    wallet = "0x" <> String.duplicate(letter, 40)
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    [actor: Human.for_account(account), context: %{client_key: did}]
  end
end

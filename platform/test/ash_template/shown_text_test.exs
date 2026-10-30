defmodule AshTemplate.ShownTextTest do
  # Words a person or an agent writes, in a room, a direct message, a note or a chat
  # with the assistant, keep their line breaks and emoji and hold no hidden
  # characters, such as the mark that shows a file's name the other way round.
  use ExUnit.Case, async: false

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.Human
  alias AshTemplate.{Chat, Dms, Notes, Rooms}

  @shown "First line\r\n\tSecond 👩\u200D💻"
  @hidden "Ada\u202Egnp.exe\nok"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    %{
      person: person("did:privy:shown-text", "e"),
      friend: person("did:privy:shown-text-friend", "f")
    }
  end

  test "a room message keeps its lines and refuses hidden characters, posted or edited", %{
    person: person
  } do
    # A room stores its line endings as \n.
    message = Rooms.post_message!(%{room: "general", body: @shown}, person)
    assert message.body == String.replace(@shown, "\r\n", "\n")

    assert refused?(Rooms.post_message(%{room: "general", body: @hidden}, person), :body)
    assert refused?(Rooms.edit_message(message, %{body: @hidden}, person), :body)
  end

  test "a direct message keeps its lines and refuses hidden characters", %{
    person: person,
    friend: friend
  } do
    said = Rooms.post_message!(%{room: "general", body: "Hello"}, friend)
    conversation = Dms.open_conversation!(said.id, person)

    assert Dms.send_dm!(conversation.id, %{body: @shown}, person).body == @shown
    assert refused?(Dms.send_dm(conversation.id, %{body: @hidden}, person), :body)
  end

  test "a note keeps its lines and refuses hidden characters in its title or body", %{
    person: person
  } do
    note = Notes.create_note!(%{title: "Seed list", body: @shown}, person)
    assert note.body == @shown

    assert refused?(Notes.create_note(%{title: "Seed list", body: @hidden}, person), :body)
    assert refused?(Notes.create_note(%{title: "Seed\nlist"}, person), :title)
    assert refused?(Notes.update_note(note, %{title: "Ada\u202Egnp.exe"}, person), :title)
    assert refused?(Notes.update_note(note, %{body: @hidden}, person), :body)
  end

  # Words saved before the rule are left as they are: Ash.Seed writes them past the
  # actions, as the site did then.
  test "an older message or note holding a hidden character is edited without it", %{
    person: person
  } do
    message =
      %{room: "general", body: "Hello"}
      |> Rooms.post_message!(person)
      |> Ash.Seed.update!(%{body: @hidden})

    assert refused?(Rooms.edit_message(message, %{body: @hidden <> "!"}, person), :body)
    assert Rooms.edit_message!(message, %{body: "Hello again"}, person).body == "Hello again"

    note =
      %{title: "Seed list", body: "Plant"}
      |> Notes.create_note!(person)
      |> Ash.Seed.update!(%{body: @hidden})

    assert Notes.update_note!(note, %{title: "Pine list", body: @hidden}, person).title ==
             "Pine list"

    assert refused?(Notes.update_note(note, %{body: @hidden <> "!"}, person), :body)
    assert Notes.update_note!(note, %{body: "Plant pines"}, person).body == "Plant pines"
  end

  test "a message to the assistant keeps its lines and refuses hidden characters", %{
    person: person
  } do
    assert Chat.create_message!(%{text: @shown}, person).text == @shown
    assert refused?(Chat.create_message(%{text: @hidden}, person), :text)
  end

  # Options to act as a new person, from their own address.
  defp person(did, letter) do
    wallet = "0x" <> String.duplicate(letter, 40)
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %AshTemplate.Actors.System{})
    [actor: Human.for_account(account), context: %{client_key: did}]
  end

  defp refused?({:error, %Ash.Error.Invalid{errors: errors}}, field),
    do: Enum.any?(errors, &match?(%{field: ^field}, &1))

  defp refused?(_result, _field), do: false
end

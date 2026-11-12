defmodule AshTemplate.Chat.ReplyTest do
  # Invariant: the assistant's reply is saved twice, unfinished when it starts
  # and whole when it ends, however many pieces it streams in; the pieces in
  # between are only broadcast, and together they are the whole reply.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Chat}
  alias AshTemplate.Actors.{Human, System}
  alias Phoenix.Socket.Broadcast

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    wallet = "0x" <> String.duplicate("c", 40)
    account = Accounts.register_verified!("did:privy:chat-reply", wallet, [wallet], actor: %System{})
    %{actor: Human.for_account(account)}
  end

  test "a reply is saved when it starts and when it ends, and only broadcast in between",
       %{actor: actor} do
    {:ok, message} = Chat.create_message(%{text: "Where do the pines go?"}, actor: actor)
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, "chat:messages:#{message.conversation_id}")

    assert %{success: 1} = Oban.drain_queue(queue: :chat_responses)

    assert [
             %Broadcast{event: "upsert_response", payload: %{complete: false, text: "", id: id}}
             | rest
           ] = received()

    {pieces, [%Broadcast{event: "upsert_response", payload: whole}]} =
      Enum.split_with(rest, &(&1.event == "piece"))

    assert %{id: ^id, complete: true, text: text} = whole
    assert length(pieces) > 1
    assert Enum.all?(pieces, &(&1.payload.id == id))
    assert Enum.map_join(pieces, & &1.payload.text) == text
    assert text =~ "Where do the pines go?"

    assert [%{id: ^id, complete: true, text: ^text}, %{id: _}] =
             Chat.message_history!(message.conversation_id, actor: actor).results
  end

  defp received do
    receive do
      %Broadcast{} = broadcast -> [broadcast | received()]
    after
      0 -> []
    end
  end
end

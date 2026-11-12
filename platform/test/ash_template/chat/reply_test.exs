defmodule AshTemplate.Chat.ReplyTest do
  # Invariant: the assistant's reply is saved twice, unfinished when it starts
  # and whole when it ends, however many pieces it streams in; the pieces in
  # between are only broadcast, and together they are the whole reply. A message
  # has one reply however many attempts write it.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo, prefix: "ash_template_app"

  alias AshTemplate.{Accounts, Chat}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Chat.Message.Workers.Respond
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

  # The first attempt's killed stream logs its exit.
  @tag :capture_log
  test "attempts cut off mid-reply and run again leave one reply, complete",
       %{actor: actor} do
    {:ok, message} = Chat.create_message(%{text: "Where do the pines go?"}, actor: actor)
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, "chat:messages:#{message.conversation_id}")
    [job] = all_enqueued(worker: Respond)

    # The first attempt stops partway through, as when its machine stops.
    first = spawn(fn -> perform_job(Respond, job.args) end)
    assert_receive %Broadcast{event: "piece", payload: %{id: id}}, 5_000
    Process.exit(first, :kill)
    received()

    assert %{success: 1} = Oban.drain_queue(queue: :chat_responses)
    perform_job(Respond, job.args)

    message_id = message.id

    assert [%{id: ^id, complete: true, text: text}, %{id: ^message_id}] =
             Chat.message_history!(message.conversation_id, actor: actor).results

    assert text =~ "Where do the pines go?"
  end

  defp received do
    receive do
      %Broadcast{} = broadcast -> [broadcast | received()]
    after
      0 -> []
    end
  end
end

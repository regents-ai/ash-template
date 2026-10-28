defmodule AshTemplate.Rooms.OperationKeyTest do
  # The operation-key rules for an agent's room post (agent access spec 4.4, C18),
  # the same on every surface because every surface calls `Rooms.agent_post`:
  # - one key sent several times at once posts one message, and every call
  #   answers that message;
  # - the same key with the same room and text answers the message it posted,
  #   whether the text is resent as first sent or as the message stored it;
  # - the same key with other text is refused as idempotency_conflict;
  # - the same key after that message was deleted is refused as message_removed,
  #   naming the message.
  #
  # The race needs separate connections that really commit, so the rows these
  # runs write stay in the test database; every run uses its own person and agent.
  use ExUnit.Case, async: false
  use ExUnitProperties

  require Ash.Query
  alias AshTemplate.{Accounts, Agents, Repo, Rooms}
  alias AshTemplate.Actors.{Agent, System}
  alias AshTemplate.Rooms.{Message, Refused}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
  end

  property "one operation key posts one message, answers it again, and refuses any other use" do
    check all(
            first <- string(:alphanumeric, min_length: 1, max_length: 40),
            rest <-
              list_of(
                one_of([
                  string(:alphanumeric, min_length: 1, max_length: 40),
                  member_of(["\n", "\n\n\n\n", "\r\n\r\n\r\n", " "])
                ]),
                max_length: 4
              ),
            gap <- member_of(["\n\n\n\n", "\r\n\r\n\r\n", "\n \n\t\n\n"]),
            last <- string(:alphanumeric, min_length: 1, max_length: 40),
            calls <- integer(2..4),
            max_runs: 8
          ) do
      # Blank lines inside the text, which the message squashes before it is stored.
      body = Enum.join([first | rest]) <> gap <> last
      {actor, account} = paired_agent()
      key = Ecto.UUID.generate()
      post = fn text -> Rooms.agent_post("general", %{body: text, operation_id: key}, actor: actor, context: %{client_key: key}) end

      answers =
        List.duplicate(body, calls)
        |> Task.async_stream(post, max_concurrency: calls)
        |> Enum.map(fn {:ok, {:ok, answer}} -> answer end)

      assert [%{replayed: false, message: %{id: id, body: stored}}] =
               Enum.reject(answers, & &1.replayed)

      assert Enum.all?(answers, &(&1.message.id == id))
      assert posts(account) == [id]

      assert {:ok, %{replayed: true, message: %{id: ^id}}} = post.(body)
      assert {:ok, %{replayed: true, message: %{id: ^id}}} = post.(stored)
      assert {:error, %{errors: [%Refused{code: "idempotency_conflict"}]}} = post.(body <> "x")

      Rooms.delete_message!(Ash.get!(Message, id, authorize?: false), actor: actor)

      assert {:error, %{errors: [%Refused{code: "message_removed", id: ^id}]}} = post.(body)
      assert posts(account) == []
    end
  end

  defp posts(account) do
    Message
    |> Ash.Query.filter(human_account_id == ^account.id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  defp paired_agent do
    did = "did:privy:operation-key-" <> Ecto.UUID.generate()
    person_wallet = wallet()
    agent_wallet = wallet()
    account = Accounts.register_verified!(did, person_wallet, [person_wallet], actor: %System{})
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: did})
    pairing = RegentAgents.pair_agent!(code.code, "Agent", :codex, actor: %RegentAgents.Agent{wallet: agent_wallet})
    record = Agents.sign_in_agent!(agent_wallet, actor: %System{})
    {Agent.paired(record, account, pairing), account}
  end

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end

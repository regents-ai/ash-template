defmodule AshTemplate.Rooms.LikesTest do
  # A message's like count moves once for each like given and each taken back, in
  # that like's own transaction, and the room's open pages hear the count itself:
  # - liking again, or taking back a like never given, moves nothing and tells
  #   nobody;
  # - likes given and taken back at the same moment are each counted;
  # - liking past the allowance is refused before any statement runs.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Limits, Repo, Rooms}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Rooms.Message

  describe "in one test's transaction" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    end

    test "each like and each like taken back moves the count once and tells the room" do
      [author, first, second] = Enum.map(1..3, fn _ -> person() end)
      message = post!(author, "Like this")
      id = message.id
      Phoenix.PubSub.subscribe(AshTemplate.PubSub, Message.topic("general"))

      like!(first, id)
      assert_receive %{event: "like", payload: %{id: ^id, like_count: 1, like_version: 1}}

      like!(first, id)
      refute_receive %{event: "like"}, 100

      like!(second, id)
      assert_receive %{event: "like", payload: %{id: ^id, like_count: 2, like_version: 2}}

      assert :ok = unlike(first, id)
      assert_receive %{event: "like", payload: %{id: ^id, like_count: 1, like_version: 3}}

      assert %{like_count: 1, like_version: 3} = Ash.get!(Message, id, authorize?: false)
    end

    test "a like past the allowance is refused before any statement runs" do
      [author, liker, other] = Enum.map(1..3, fn _ -> person() end)
      message = post!(author, "Like this, quickly")

      # An accepted like shows its transaction and its writes.
      accepted = capture_statements(fn -> like(other, message.id) end)
      assert {:ok, _like} = accepted.result
      assert Enum.any?(accepted.sql, &transaction_or_write?/1)

      spend_all(:like, {:human, liker.id})
      statements = capture_statements(fn -> like(liker, message.id) end)

      assert {:error, %Ash.Error.Invalid{errors: [%{field: :message_id, vars: vars}]}} =
               statements.result

      assert vars[:retry_after] in 1..60
      assert statements.sql == []
      assert %{like_count: 1} = Ash.get!(Message, message.id, authorize?: false)
    end
  end

  describe "with real commits" do
    # The race needs separate connections that really commit.
    setup do
      AshTemplate.RealCommits.start()
    end

    test "likes given and taken back at the same moment are each counted" do
      author = person()
      likers = Enum.map(1..8, fn _ -> person() end)
      message = post!(author, "Everyone at once")

      at_once(likers, &like!(&1, message.id))
      assert %{like_count: 8, like_version: 8} = Ash.get!(Message, message.id, authorize?: false)

      # One person pressing four times at once likes it once.
      at_once(List.duplicate(author, 4), &like!(&1, message.id))
      assert %{like_count: 9} = Ash.get!(Message, message.id, authorize?: false)

      at_once(likers, &(:ok = unlike(&1, message.id)))
      assert %{like_count: 1} = Ash.get!(Message, message.id, authorize?: false)
    end
  end

  defp at_once(people, press) do
    people
    |> Task.async_stream(press, max_concurrency: length(people))
    |> Enum.each(fn {:ok, _done} -> :ok end)
  end

  defp person do
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    Accounts.register_verified!("did:privy:likes-" <> Ecto.UUID.generate(), wallet, [wallet], actor: %System{})
  end

  defp post!(account, body) do
    Rooms.post_message!(%{room: "general", body: body},
      actor: Human.for_account(account),
      context: %{client_key: account.id}
    )
  end

  defp like(account, id),
    do: Rooms.like_message(id, actor: Human.for_account(account), context: %{client_key: account.id})

  defp like!(account, id), do: {:ok, _like} = like(account, id)

  defp unlike(account, id) do
    actor = Human.for_account(account)

    case Rooms.get_my_like(id, actor: actor) do
      {:ok, nil} -> :ok
      {:ok, like} -> Rooms.unlike(like, actor: actor, context: %{client_key: account.id})
    end
  end

  defp spend_all(allowance, who) do
    Stream.repeatedly(fn -> Limits.spend(allowance, who) end)
    |> Enum.find(&(&1 == :limited))
  end

  # Every statement the repo runs while `fun` runs in this process.
  defp capture_statements(fun) do
    handler = "likes-test-#{:erlang.unique_integer()}"
    test = self()

    :telemetry.attach(handler, [:ash_template, :repo, :query], fn _event, _measure, meta, _config ->
      send(test, {:statement, meta.query})
    end, nil)

    result = fun.()
    :telemetry.detach(handler)
    %{result: result, sql: collect([])}
  end

  defp collect(sql) do
    receive do
      {:statement, query} -> collect([query | sql])
    after
      0 -> Enum.reverse(sql)
    end
  end

  defp transaction_or_write?(sql),
    do: String.match?(sql, ~r/\A\s*(begin|savepoint|insert|update|delete)\b/i)
end

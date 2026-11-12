defmodule AshTemplate.Polls.VoteNoticesTest do
  # Invariant: a vote is counted on its poll's row as it is saved, and what anyone
  # hears or reads of an open poll says how many have voted, never which way. The
  # poll's own topic hears each vote; the site-wide topic hears only a start and an
  # end. Each choice's count is read once the poll has closed.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Polls}
  alias AshTemplate.Actors.{Human, System}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "votes are heard as a count on the poll's own topic, and the counts appear once it closes" do
    [starter | voters] = for digit <- ~w(c d e f), do: person(digit)
    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Polls.topic())

    poll =
      Polls.start_poll!(%{question: "Lunch", choices: ["Soup", "Salad"], minutes: 5},
        actor: starter
      )

    assert_receive %{topic: "public:polls", event: "start", payload: started}
    assert started == Map.take(poll, [:id, :question, :closes_at, :ended_at, :votes_cast])

    Phoenix.PubSub.subscribe(AshTemplate.PubSub, Polls.topic(poll.id))

    for {voter, choice} <- Enum.zip(voters, ["Soup", "Salad", "Soup"]),
        do: Polls.vote!(poll.id, %{choice: choice}, actor: voter)

    for count <- 1..3 do
      assert_receive %{topic: "public:poll:" <> _, event: "vote", payload: payload}
      assert payload == %{id: poll.id, votes_cast: count}
    end

    refute_received %{topic: "public:polls"}
    assert %{votes_cast: 3, totals: nil} = Polls.get_poll!(poll.id)

    # A voter asking again is answered with their vote, and nothing is counted twice.
    Polls.vote!(poll.id, %{choice: "Soup"}, actor: hd(voters))
    refute_receive %{event: "vote"}

    Polls.end_poll!(Polls.get_poll!(poll.id, actor: starter), actor: starter)
    assert_receive %{topic: "public:polls", event: "end", payload: ended}
    assert Map.keys(ended) |> Enum.sort() == [:closes_at, :ended_at, :id, :question, :votes_cast]
    assert ended.votes_cast == 3

    assert %{totals: [%{choice: "Soup", votes: 2}, %{choice: "Salad", votes: 1}]} =
             Polls.get_poll!(poll.id)

    # After the end, a first vote is turned away whole: neither saved nor counted.
    assert {:error, %Ash.Error.Invalid{}} =
             Polls.vote(poll.id, %{choice: "Salad"}, actor: person("1"))

    refute_receive %{event: "vote"}
    assert %{votes_cast: 3} = Polls.get_poll!(poll.id)
  end

  defp person(digit) do
    wallet = "0x" <> String.duplicate(digit, 40)

    "did:privy:vote-notices-#{digit}"
    |> Accounts.register_verified!(wallet, [wallet], actor: %System{})
    |> Human.for_account()
  end
end

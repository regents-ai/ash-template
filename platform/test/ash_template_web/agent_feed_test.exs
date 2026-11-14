defmodule AshTemplateWeb.AgentFeedTest do
  # Invariant: a signed agent's feed tells it only of what it could already read
  # through the ordinary routes, the moment it is posted, never the words; one
  # feed per agent; a reconnect gets what it missed. Each feed is read through a
  # real listener, as an agent's command line reads it.
  use ExUnit.Case, async: false

  import Plug.Conn

  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.Human
  alias AshTemplate.{Dms, Rooms}
  alias AshTemplateWeb.Plugs.AgentWallet

  # Each proof the stand-in sign-in service accepts, and the wallet it vouches for.
  @wallets %{
    "proof-paired" => "0x2222222222222222222222222222222222222222",
    "proof-other-agent" => "0x6666666666666666666666666666666666666666",
    "proof-third-agent" => "0x5555555555555555555555555555555555555555"
  }

  # The first of `people/1`'s accounts, who chose no name, so an event names them by it.
  @other "0x" <> String.duplicate("7", 40)

  setup do
    :ets.delete_all_objects(AshTemplate.Accounts.RequestRateLimiter)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    old = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})
    Req.Test.set_req_test_to_shared()

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)

      case old do
        {:ok, opts} -> Application.put_env(:regent_agents, :req_options, opts)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = read_body(conn)

      case Map.fetch(@wallets, Jason.decode!(body)["headers"]["x-siwa-signature"]) do
        {:ok, wallet} ->
          Req.Test.json(conn, %{
            code: "http_envelope_valid",
            data: %{
              verified: true,
              walletAddress: wallet,
              agentBook: nil,
              agentRegistration: nil,
              principal: %{
                kind: "wallet",
                wallet_address: wallet,
                chain_id: 8453,
                audience: "ash-template"
              }
            }
          })

        :error ->
          conn
          |> put_status(401)
          |> Req.Test.json(%{
            error: %{code: "http_headers_missing", message: "Signed agent proof required"}
          })
      end
    end)

    listener =
      start_supervised!(
        {Bandit,
         plug: AshTemplateWeb.Endpoint, ip: :loopback, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)
    {:ok, url: "http://127.0.0.1:#{port}/api/v1/feed"}
  end

  test "a paired agent hears a direct message to its person at once, without its words, and nothing from conversations its person is not in",
       %{url: url} do
    {person, _pairing} = paired_person("did:privy:feed-dm")
    [other, third] = people(["did:privy:feed-other", "did:privy:feed-third"])
    conversation = conversation(person, other)
    elsewhere = conversation(other, third)

    feed = open_feed(url, "proof-paired")
    assert next_frame(feed) == ": keep-alive"

    sent = Dms.send_dm!(conversation.id, %{body: "Are you there?"}, actor: other)
    event = next_event(feed)

    assert event.data == %{
             "kind" => "dm",
             "id" => sent.id,
             "at" => DateTime.to_iso8601(sent.inserted_at),
             "conversation_id" => conversation.id,
             "author" => %{"kind" => "person", "name" => nil, "wallet" => @other, "ens_name" => nil},
             "read" => "POST /api/v1/dms/#{conversation.id}/history"
           }

    assert event.id == Integer.to_string(DateTime.to_unix(sent.inserted_at, :microsecond))
    refute event.raw =~ "Are you there?"

    # What the person sends, and what two other people say to each other, is not news.
    Dms.send_dm!(conversation.id, %{body: "Yes"}, actor: person)
    Dms.send_dm!(elsewhere.id, %{body: "Private"}, actor: third)
    assert next_frame(feed) == ": keep-alive"

    # A conversation the person blocked stays quiet.
    Dms.block_conversation!(conversation, actor: person)
    Dms.send_dm!(conversation.id, %{body: "Still here"}, actor: other)
    assert next_frame(feed) == ": keep-alive"
  end

  test "an agent hears posts in a room only once it has posted there, and never its own",
       %{url: url} do
    paired_person("did:privy:feed-room")
    [other] = people(["did:privy:feed-room-other"])
    {:ok, agent} = AgentWallet.actor_for(@wallets["proof-paired"])
    feed = open_feed(url, "proof-paired")
    assert next_frame(feed) == ": keep-alive"

    post!(other, "Before you came")
    assert next_frame(feed) == ": keep-alive"

    post!(agent, "Hello from the agent")
    assert next_frame(feed) == ": keep-alive"

    reply = post!(other, "Welcome")
    event = next_event(feed)

    assert event.data == %{
             "kind" => "room_post",
             "id" => reply.id,
             "at" => DateTime.to_iso8601(reply.inserted_at),
             "room" => "general",
             "author" => %{"kind" => "person", "name" => nil, "wallet" => @other, "ens_name" => nil},
             "read" => "GET /api/v1/rooms/general/messages/#{reply.id}"
           }

    refute event.raw =~ "Welcome"
  end

  test "a request with no signature, or one the sign-in service refuses, opens no feed",
       %{url: url} do
    unsigned = Req.get!(url, retry: false)
    assert unsigned.status == 401

    refused = Req.get!(url, headers: [{"x-siwa-signature", "forged"}], retry: false)
    assert refused.status == 401
    assert refused.body["error"]["code"] == "http_headers_missing"
  end

  test "a second feed for the same agent closes the first", %{url: url} do
    paired_person("did:privy:feed-twice")
    first = open_feed(url, "proof-paired")
    assert next_frame(first) == ": keep-alive"

    second = open_feed(url, "proof-paired")

    assert next_event(first).data == %{"kind" => "closed", "reason" => "replaced"}
    assert_receive {:feed_done, ref}
    assert ref == first.ref
    assert next_frame(second) == ": keep-alive"
  end

  test "a pairing that ends closes the feed, so the agent reconnects as it now is",
       %{url: url} do
    {_person, pairing} = paired_person("did:privy:feed-unpair")
    feed = open_feed(url, "proof-paired")
    assert next_frame(feed) == ": keep-alive"

    person = %RegentAgents.Person{privy_user_id: "did:privy:feed-unpair"}
    :ok = RegentAgents.unpair_agent(pairing, actor: person)
    # The site hears of a pairing change through the database, as from any site.
    Phoenix.PubSub.broadcast(
      AshTemplate.PubSub,
      RegentAgents.topic(person.privy_user_id),
      :agents_changed
    )

    assert next_event(feed).data == %{"kind" => "closed", "reason" => "pairing_changed"}
    assert_receive {:feed_done, ref}
    assert ref == feed.ref
  end

  test "a reconnect with Last-Event-ID gets what it missed, oldest first, and an id that is not one gets a resync",
       %{url: url} do
    {person, _pairing} = paired_person("did:privy:feed-resume")
    [other] = people(["did:privy:feed-resume-other"])
    conversation = conversation(person, other)

    feed = open_feed(url, "proof-paired")
    assert next_frame(feed) == ": keep-alive"
    Dms.send_dm!(conversation.id, %{body: "One"}, actor: other)
    last = next_event(feed)
    stop_feed(feed)

    missed =
      for body <- ["Two", "Three"],
          do: Dms.send_dm!(conversation.id, %{body: body}, actor: other).id

    again = open_feed(url, "proof-paired", [{"last-event-id", last.id}])
    assert [next_event(again).data["id"], next_event(again).data["id"]] == missed
    assert next_frame(again) == ": keep-alive"
    stop_feed(again)

    lost = open_feed(url, "proof-paired", [{"last-event-id", "yesterday"}])
    assert next_event(lost).data == %{"kind" => "resync"}
  end

  test "past the machine's limit a feed is refused", %{url: url} do
    paired_person("did:privy:feed-full")
    setting = Application.fetch_env!(:ash_template, AshTemplateWeb.FeedController)
    on_exit(fn -> Application.put_env(:ash_template, AshTemplateWeb.FeedController, setting) end)

    Application.put_env(
      :ash_template,
      AshTemplateWeb.FeedController,
      Keyword.put(setting, :max_open, 1)
    )

    feed = open_feed(url, "proof-paired")
    assert next_frame(feed) == ": keep-alive"

    full = Req.get!(url, headers: [{"x-siwa-signature", "proof-other-agent"}], retry: false)
    assert full.status == 503
    assert full.body["error"]["code"] == "feed_full"
  end

  test "a paired agent gets a feed while unpaired ones hold their whole share", %{url: url} do
    paired_person("did:privy:feed-share")
    setting = Application.fetch_env!(:ash_template, AshTemplateWeb.FeedController)
    on_exit(fn -> Application.put_env(:ash_template, AshTemplateWeb.FeedController, setting) end)

    Application.put_env(
      :ash_template,
      AshTemplateWeb.FeedController,
      Keyword.merge(setting, max_open: 3, max_unpaired: 1)
    )

    unpaired = open_feed(url, "proof-other-agent")
    assert next_frame(unpaired) == ": keep-alive"

    turned_away =
      Req.get!(url, headers: [{"x-siwa-signature", "proof-third-agent"}], retry: false)

    assert turned_away.status == 503
    assert turned_away.body["error"]["code"] == "feed_full"

    paired = open_feed(url, "proof-paired")
    assert next_frame(paired) == ": keep-alive"
  end

  # Reads the feed in its own process and sends each whole frame here.
  defp open_feed(url, proof, headers \\ []) do
    test = self()
    ref = make_ref()

    pid =
      spawn_link(fn ->
        Req.get!(url,
          headers: [{"x-siwa-signature", proof} | headers],
          retry: false,
          receive_timeout: 10_000,
          into: fn {:data, data}, {req, resp} ->
            buffer = Req.Response.get_private(resp, :buffer, "") <> data
            {frames, [rest]} = buffer |> String.split("\n\n") |> Enum.split(-1)
            Enum.each(frames, &send(test, {:feed_frame, ref, resp.status, &1}))
            {:cont, {req, Req.Response.put_private(resp, :buffer, rest)}}
          end
        )

        send(test, {:feed_done, ref})
      end)

    %{ref: ref, pid: pid}
  end

  defp stop_feed(%{pid: pid}) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
  end

  defp next_frame(%{ref: ref}) do
    assert_receive {:feed_frame, ^ref, 200, frame}
    frame
  end

  # The next event, past at most a few keep-alive lines.
  defp next_event(feed, keep_alives \\ 3) do
    case next_frame(feed) do
      ": keep-alive" when keep_alives > 0 ->
        next_event(feed, keep_alives - 1)

      frame ->
        fields =
          for line <- String.split(frame, "\n"), into: %{} do
            [name, value] = String.split(line, ": ", parts: 2)
            {name, value}
          end

        %{id: fields["id"], data: Jason.decode!(fields["data"]), raw: frame}
    end
  end

  defp paired_person(privy_user_id) do
    wallet = @wallets["proof-paired"]

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "test-session",
        privy_user_id: privy_user_id,
        wallet_address: wallet,
        wallet_addresses: [wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    person = %RegentAgents.Person{privy_user_id: privy_user_id}
    code = RegentAgents.issue_pairing_code!(actor: person)

    pairing =
      RegentAgents.pair_agent!(code.code, "Fixture", :codex,
        actor: %RegentAgents.Agent{wallet: wallet}
      )

    {Human.for_account(account), pairing}
  end

  defp people(ids) do
    for {id, n} <- Enum.with_index(ids, 7) do
      wallet = "0x" <> String.duplicate(Integer.to_string(n), 40)

      id
      |> AshTemplate.Accounts.register_verified!(wallet, [wallet], actor: %AshTemplate.Actors.System{})
      |> Human.for_account()
    end
  end

  # The conversation `a` opens from a room message `b` wrote.
  defp conversation(a, b) do
    said = post!(b, "Write to me")
    Dms.open_conversation!(said.id, actor: a)
  end

  defp post!(actor, body) do
    Rooms.post_message!(%{room: "general", body: body},
      actor: actor,
      context: %{client_key: "feed-#{System.unique_integer([:positive])}"}
    )
  end
end

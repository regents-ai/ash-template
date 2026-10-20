defmodule AshTemplate.SignedToolsTest do
  # Invariant: neither a browser cookie nor an unpaired/revoked SIWA identity
  # grants account access, and each accepted proof is checked exactly once.
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn
  require Ash.Query
  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Rooms

  @wallet "0x2222222222222222222222222222222222222222"
  @other "0x4444444444444444444444444444444444444444"

  test "Points settlement shares the account cap and per-action count across actors and retries" do
    # Accepted invariant: transport/actor changes cannot create another reward allowance.
    alias RegentPoints, as: Points
    alias RegentPoints.{Rules, Store}
    starts_at = Application.get_env(:regent_points, :starts_at)
    on_exit(fn -> Application.put_env(:regent_points, :starts_at, starts_at) end)
    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])

    account =
      AshTemplate.Accounts.register_verified!("did:privy:points-test", @wallet, [@wallet],
        actor: %AshTemplate.Actors.System{}
      )

    Points.open_account!(%{id: account.id}, actor: Store.system())
    at = ~U[2020-01-03 12:00:00Z]
    reply = "patchbay.reply_published"

    event = fn rule_id, kind, time ->
      id = Ecto.UUID.generate()
      rule = Enum.find(Rules.catalog(), &(&1["id"] == rule_id))

      Points.create_event!(
        %{
          program_id: Rules.program(),
          source_app: "patchbay",
          source_kind: "reply",
          source_event_key: id,
          rule_id: rule_id,
          account_id: account.id,
          actor_kind: kind,
          actor_id: id,
          source_action_at: time,
          qualified_at: time,
          evidence_ref: id,
          payload_digest: id,
          evidence: %{"attribution_link_id" => id},
          rule_snapshot: rule,
          award_key: id
        },
        actor: Store.system()
      )
    end

    first = event.(reply, "human", at)
    second = event.(reply, "agent", at)

    assert {:ok, %{status: :confirmed}} = Points.process_event(first.id, actor: Store.system())
    assert {:ok, %{status: :capped}} = Points.process_event(second.id, actor: Store.system())
    assert {:ok, %{status: :confirmed}} = Points.process_event(first.id, actor: Store.system())
    assert length(
             Points.read_entries!(
               query: Ash.Query.filter(RegentPoints.Entry, account_id == ^account.id),
               actor: Store.system()
             )
           ) == 2
    day_two = DateTime.add(at, 1, :day)
    cap = Store.cap(account.id, Rules.program(), "activity:account", Rules.window("day", day_two))
    Points.consume_cap!(cap, 95_000_000, actor: Store.system())

    assert {:ok, %{status: :confirmed}} =
             Points.process_event(event.(reply, "agent", day_two).id, actor: Store.system())

    # Another rule, another actor: the day's limit is the account's, so it is spent.
    assert {:ok, %{status: :capped}} =
             Points.process_event(
               event.("patchbay.report_published", "human", day_two).id,
               actor: Store.system()
             )

    assert Store.cap(
             account.id,
             Rules.program(),
             "activity:account",
             Rules.window("day", day_two)
           ).points_micro == 100_000_000
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    old = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)

      case old do
        {:ok, opts} -> Application.put_env(:regent_agents, :req_options, opts)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = read_body(conn)
      envelope = Jason.decode!(body)
      send(self(), {:proof_checked, envelope})

      if envelope["headers"]["x-siwa-signature"] == "fixture-proof" do
        Req.Test.json(conn, %{
          code: "http_envelope_valid",
          data: %{
            verified: true,
            walletAddress: @wallet,
            agentBook: nil,
            agentRegistration: nil,
            principal: %{
              kind: "wallet",
              wallet_address: @wallet,
              chain_id: 8453,
              audience: "ash-template"
            }
          }
        })
      else
        conn
        |> put_status(401)
        |> Req.Test.json(%{
          error: %{
            code: "http_headers_missing",
            message: "Signed agent proof required",
            hint: "Sign with SIWA"
          }
        })
      end
    end)

    :ok
  end

  defp request(method, path, body \\ nil, proof \\ true) do
    conn = conn(method, path, body)
    conn = if body, do: put_req_header(conn, "content-type", "application/json"), else: conn
    conn = if proof, do: put_req_header(conn, "x-siwa-signature", "fixture-proof"), else: conn

    conn
    |> put_req_header("cookie", "privy-token=not-agent-authority")
    |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))
  end

  test "an agent whose person has not signed in here yet is asked for that sign-in, never told the account is missing" do
    # Founder rule (16 Oct 2026): every account exists on every site; an agent is
    # only ever told its person hasn't signed in here yet, then checks in once they have.
    person = %RegentAgents.Person{privy_user_id: "did:privy:first-visit"}
    code = RegentAgents.issue_pairing_code!(actor: person)

    RegentAgents.pair_agent!(code.code, "Fixture", :hermes,
      actor: %RegentAgents.Agent{wallet: @wallet}
    )

    refused = request(:get, "/api/agents/v1/me")
    assert refused.status == 403
    error = Jason.decode!(refused.resp_body)["error"]
    assert error["code"] == "person_not_here"
    assert error["message"] =~ "hasn't signed in on this site yet"
    assert error["hint"] =~ "Ask your person to sign in"
    refute refused.resp_body =~ ~r/no account|account (is )?missing/i
    assert_status("person_not_here")

    assert {:ok, _account, []} =
             VerifiedSession.establish(%RegentPrivy.Session{
               app_id: "test-app",
               session_id: "test-session",
               privy_user_id: person.privy_user_id,
               wallet_address: "0x3333333333333333333333333333333333333333",
               wallet_addresses: ["0x3333333333333333333333333333333333333333"],
               linked_socials: []
             })

    checked_in = request(:get, "/api/agents/v1/me")
    assert checked_in.status == 200, checked_in.resp_body
    assert Jason.decode!(checked_in.resp_body)["data"]["account"] != nil
    assert_status("paired")
  end

  defp assert_status(status) do
    whoami = request(:get, "/api/agents/v1/whoami")
    assert whoami.status == 200, whoami.resp_body
    data = Jason.decode!(whoami.resp_body)["data"]
    assert data["status"] == status
    assert data["allowed"] == Map.fetch!(Application.fetch_env!(:regent_agents, :allowed), status)
    assert data["next_step"] == RegentAgents.HTTP.next_step(status)
  end

  test "private note flow preserves the agent, exact signed bytes and revocation boundary without World ID" do
    # Mock broker verification, real shared probe and product refusal; not live SIWA acceptance.
    probe = request(:get, "/api/agents/v1/whoami")
    assert probe.status == 200
    access = Jason.decode!(probe.resp_body)["data"]
    assert access["authenticated"] == true
    assert access["pairing"] == nil
    assert access["status"] == "not_paired"
    assert access["allowed"] == Application.fetch_env!(:regent_agents, :allowed)["not_paired"]
    assert_receive {:proof_checked, %{"path" => "/api/agents/v1/whoami"}}
    refute_receive {:proof_checked, _}

    for {method, path, body} <- [
          {:get, "/api/v1/notes", nil},
          {:post, "/api/v1/notes",
           Jason.encode!(%{title: "Refused", operation_id: Ecto.UUID.generate()})},
          {:get, "/api/v1/account/balances", nil}
        ] do
      refused = request(method, path, body)
      assert refused.status == 403
      error = Jason.decode!(refused.resp_body)["error"]
      assert error["code"] == "agent_not_paired"
      assert error["hint"] =~ "Pair New Agent"
      refute Map.has_key?(Jason.decode!(refused.resp_body), "notes")
      assert_receive {:proof_checked, _}
    end

    session = %RegentPrivy.Session{
      app_id: "test-app",
      session_id: "test-session",
      privy_user_id: "did:privy:tool-test",
      wallet_address: @wallet,
      wallet_addresses: [@wallet],
      linked_socials: []
    }

    assert {:ok, account, []} = VerifiedSession.establish(session)
    person = %RegentAgents.Person{privy_user_id: session.privy_user_id}
    code = RegentAgents.issue_pairing_code!(actor: person)

    paired =
      RegentAgents.pair_agent!(code.code, "Fixture", :codex,
        actor: %RegentAgents.Agent{wallet: @wallet}
      )

    # A cookie with no signature is a person's request with no sign-in: refused
    # before any proof is checked.
    assert request(:get, "/api/v1/notes", nil, false).status == 401
    refute_receive {:proof_checked, _}
    id = Ecto.UUID.generate()
    body = Jason.encode!(%{title: "Paired note", operation_id: id})
    created = request(:post, "/api/v1/notes", body)
    assert created.status == 201, created.resp_body
    digest = Siwa.content_digest_for_body(body)
    assert_receive {:proof_checked, %{"path" => "/api/v1/notes", "body_digest" => ^digest}}
    refute_receive {:proof_checked, _}
    note = Jason.decode!(created.resp_body)["note"]
    assert note["id"] == id
    assert note["changed_by_agent"] != nil
    assert request(:get, "/api/v1/notes/" <> id).status == 200
    assert request(:get, "/api/v1/account/balances").status == 200
    assert request(:get, "/api/v1/account/points").status == 200
    assert request(:post, "/api/v1/account/credits/history", "{}").status == 200
    retried = request(:post, "/api/v1/notes", body)
    assert retried.status == 200
    assert Jason.decode!(retried.resp_body)["note"]["id"] == id

    assert request(:post, "/api/v1/notes", Jason.encode!(%{title: "Missing operation"})).status ==
             422

    assert length(
             AshTemplate.Notes.list_my_notes!(
               actor: AshTemplate.Actors.Human.for_account(account)
             )
           ) == 1

    assert :ok = RegentAgents.unpair_agent(paired, actor: person)

    human = AshTemplate.Actors.Human.for_account(account)
    original = AshTemplate.Notes.get_my_note!(id, actor: human)
    AshTemplate.Notes.update_note!(original, %{title: "Edited by owner"}, actor: human)

    assert {:ok, %{actor_id: episode}} =
             AshTemplate.Points.AgentNote.verify(%{"source_event_key" => id})

    assert episode == paired.id

    saved =
      AshTemplate.Notes.get_my_note!(id, actor: AshTemplate.Actors.Human.for_account(account))

    assert {:error, error} =
             saved
             |> Ash.Changeset.for_update(:send_webhook, %{},
               context: %{
                 ash_oban: %{
                   job: %Oban.Job{
                     args: %{"revision" => saved.revision, "pairing_id" => paired.id}
                   }
                 }
               }
             )
             |> Ash.update(authorize?: false)

    assert inspect(error) =~ "pairing_revoked"

    assert request(:get, "/api/v1/notes/" <> id).status in [401, 403]
    assert request(:post, "/api/v1/notes", body).status in [401, 403]
  end

  test "an agent mutes and unmutes only for its own person, and only while paired" do
    # Invariant: a mute an agent adds is its person's, as if they pressed Mute, and it
    # can never read or lift another person's mute.
    {account, person, paired} = paired_person("did:privy:mute-test")
    human = AshTemplate.Actors.Human.for_account(account)

    other =
      AshTemplate.Accounts.register_verified!("did:privy:mute-other", @other, [@other],
        actor: %AshTemplate.Actors.System{}
      )

    other_human = AshTemplate.Actors.Human.for_account(other)
    message =
      Rooms.post_message!(%{room: "general", body: "Hello from the other side"},
        actor: other_human,
        context: %{client_key: "other"}
      )

    # A signed body reaches the action whole: the search finds the message to mute.
    found = request(:post, "/api/v1/rooms/search", Jason.encode!(%{text: "other side"}))
    assert found.status == 200, found.resp_body
    assert [%{"id" => id}] = Jason.decode!(found.resp_body)["messages"]
    assert id == message.id

    added = request(:post, "/api/v1/mutes", Jason.encode!(%{message_id: message.id}))
    assert added.status == 200, added.resp_body
    mute = Jason.decode!(added.resp_body)["mute"]
    assert mute["author_kind"] == "person"
    assert Enum.map(Rooms.list_my_mutes!(actor: human), & &1.id) == [mute["id"]]

    # Muting again keeps the one mute.
    assert request(:post, "/api/v1/mutes", Jason.encode!(%{message_id: message.id})).status == 200
    listed = Jason.decode!(request(:get, "/api/v1/mutes").resp_body)["mutes"]
    assert Enum.map(listed, & &1["id"]) == [mute["id"]]

    # Another person's mute answers as a missing one, and stays.
    own =
      Rooms.post_message!(%{room: "general", body: "Mine"},
        actor: human,
        context: %{client_key: "person"}
      )
    theirs = Rooms.mute_author!(own.id, actor: other_human)
    assert error_code(request(:delete, "/api/v1/mutes/" <> theirs.id)) == "mute_not_found"
    assert {:ok, %Rooms.Mute{}} = Rooms.get_my_mute(theirs.id, actor: other_human)

    # The person's own message cannot be muted for them.
    assert error_code(request(:post, "/api/v1/mutes", Jason.encode!(%{message_id: own.id}))) ==
             "invalid_mute"

    removed = request(:delete, "/api/v1/mutes/" <> mute["id"])
    assert Jason.decode!(removed.resp_body) == %{"removed" => true, "id" => mute["id"]}
    assert Rooms.list_my_mutes!(actor: human) == []

    assert :ok = RegentAgents.unpair_agent(paired, actor: person)
    added_after = request(:post, "/api/v1/mutes", Jason.encode!(%{message_id: message.id}))
    assert added_after.status == 403
    assert Rooms.list_my_mutes!(actor: human) == []
  end

  test "an agent reads its person's activity a page at a time, each notification once, marking none read" do
    {account, _person, _paired} = paired_person("did:privy:activity-test")
    human = AshTemplate.Actors.Human.for_account(account)

    Ash.bulk_create!(
      for(n <- 1..51, do: %{human_account_id: account.id, title: "Notice #{n}", path: "/notes"}),
      AshTemplate.Activity.Notification,
      :notify,
      actor: %AshTemplate.Actors.System{}
    )

    first = request(:post, "/api/v1/activity", "{}")
    assert first.status == 200, first.resp_body

    %{"notifications" => newest, "pagination" => %{"has_more" => true, "next_cursor" => cursor}} =
      Jason.decode!(first.resp_body)

    second = request(:post, "/api/v1/activity", Jason.encode!(%{after: cursor}))
    assert second.status == 200, second.resp_body

    %{"notifications" => older, "pagination" => %{"has_more" => false, "next_cursor" => nil}} =
      Jason.decode!(second.resp_body)

    assert {length(newest), length(older)} == {50, 1}
    assert (newest ++ older) |> Enum.uniq_by(& &1["id"]) |> length() == 51

    for body <- [%{after: cursor, limit: 5}, %{after: 5}, %{limit: 5}] do
      assert error_code(request(:post, "/api/v1/activity", Jason.encode!(body))) ==
               "invalid_activity_request"
    end

    assert error_code(request(:post, "/api/v1/activity", Jason.encode!(%{after: "nope"}))) ==
             "invalid_cursor"

    assert {:ok, 51} = AshTemplate.Activity.count_unread(actor: human)
  end

  defp paired_person(privy_user_id) do
    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "test-session",
        privy_user_id: privy_user_id,
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: []
      })

    person = %RegentAgents.Person{privy_user_id: privy_user_id}
    code = RegentAgents.issue_pairing_code!(actor: person)

    paired =
      RegentAgents.pair_agent!(code.code, "Fixture", :codex,
        actor: %RegentAgents.Agent{wallet: @wallet}
      )

    {account, person, paired}
  end

  defp error_code(conn), do: Jason.decode!(conn.resp_body)["error"]["code"]
end

defmodule AshTemplateWeb.PointsPageTest do
  # What a signed-in person gets from Points on the first render, with no wait:
  # their own figures, the actions still open with where to do them, and their own
  # row on the leaderboard beside other people's public names. Awards are earned the
  # way the site earns them: an account is made, and the queued checks are run.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.Actors.System

  @endpoint AshTemplateWeb.Endpoint
  @wallet "0x" <> String.duplicate("b", 40)
  @other "0x" <> String.duplicate("9", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    previous = Map.new([:starts_at, :approved_rules], &{&1, Application.get_env(:regent_points, &1)})
    Application.put_env(:regent_points, :starts_at, ~U[2020-01-01 00:00:00Z])
    Application.put_env(:regent_points, :approved_rules, ~w(account.activated social.x))

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> Application.put_env(:regent_points, key, value) end)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    other = Accounts.register_verified!("did:privy:points-page-other", @other, [@other], actor: %System{})

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "points-page",
        privy_user_id: "did:privy:points-page",
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: [],
        issued_at: :os.system_time(:second),
        expires_at: :os.system_time(:second) + 3600
      })

    # The account's time is kept to the second, rounded, so it can be up to half a
    # second ahead; Points' check waits for it.
    Process.sleep(1_000)
    assert %{failure: 0} = Oban.drain_queue(queue: :points, with_recursion: true)

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)

    conn =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> Plug.Test.init_test_session(SessionAuthority.session(claim))

    %{conn: conn, other: other, person: account}
  end

  test "the first render carries the person's figures, open actions and place", %{conn: conn} do
    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()

    assert text(page, "#points-total .rg-points-total__figure") == "25"
    assert text(page, "#points-total dl") =~ "+25"
    assert text(page, "#points-total dl") =~ "#1"

    # The account's own award is ticked; the social link is open and says where to go.
    assert text(page, ~s(#points-todo li[data-done="true"])) =~ "Account activated"
    assert LazyHTML.attribute(LazyHTML.query(page, ~s(#points-todo li[data-done="false"] a)), "href") ==
             ["/account/connections"]

    # Two accounts level on points share first place; only the reader's row is marked.
    assert page |> LazyHTML.query("#points-board li") |> Enum.count() == 2
    assert page |> LazyHTML.query(~s(#points-board li[data-you="true"])) |> Enum.count() == 1
    refute text(page, "#points-page") =~ "Loading"
  end

  # Another person's row shows the name the site shows the public and their total:
  # never their wallet in full or anything else about the account.
  test "the leaderboard shows other people by public name only", %{conn: conn, other: other} do
    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()
    row = text(page, ~s(#points-board li[data-you="false"]))

    assert row =~ AshTemplate.PublicIdentity.label(Ash.load!(other, [:display_name, :ens_name], actor: %System{}))
    refute row =~ @other
    refute row =~ other.privy_user_id
  end

  # A person's paired agent reads the same figures the page shows, and its copy of
  # the leaderboard carries a place, a public name and a total for each row.
  test "a paired agent is answered with the page's figures", %{conn: conn, person: person} do
    page = conn |> get("/account/points") |> html_response(200) |> LazyHTML.from_document()
    answer = agent_answer(person)

    assert answer["points"] == text(page, "#points-total .rg-points-total__figure")
    assert "#" <> to_string(answer["rank"]) == "#1"
    assert answer["earned_today"] == "25"

    assert %{"done" => true, "left" => false} = Enum.find(answer["to_do"], &(&1["label"] == "Account activated"))
    assert %{"done" => false, "left" => true} = Enum.find(answer["to_do"], &(&1["label"] == "X account linked"))

    assert length(answer["leaderboard"]) == page |> LazyHTML.query("#points-board li") |> Enum.count()

    for row <- answer["leaderboard"] do
      assert row |> Map.keys() |> Enum.sort() == ~w(name points rank you)
    end
  end

  test "a signed-out visitor is asked to sign in and sees no figures" do
    page =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> get("/account/points")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert Enum.count(LazyHTML.query(page, "#points-signed-out")) == 1
    assert Enum.empty?(LazyHTML.query(page, "#points-total"))
    assert Enum.empty?(LazyHTML.query(page, "#points-board"))
  end

  # Pairs an agent with the person and asks for Points as that agent; the sign-in
  # service's check of the agent's signature is answered here.
  defp agent_answer(person) do
    previous = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})

    on_exit(fn ->
      case previous do
        {:ok, options} -> Application.put_env(:regent_agents, :req_options, options)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        code: "http_envelope_valid",
        data: %{
          verified: true,
          walletAddress: @wallet,
          agentBook: nil,
          agentRegistration: nil,
          principal: %{kind: "wallet", wallet_address: @wallet, chain_id: 8453, audience: "ash-template"}
        }
      })
    end)

    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: person.privy_user_id})
    RegentAgents.pair_agent!(code.code, "Fixture", :codex, actor: %RegentAgents.Agent{wallet: @wallet})

    build_conn()
    |> put_req_header("x-siwa-signature", "fixture-proof")
    |> get("/api/v1/account/points")
    |> json_response(200)
  end

  defp text(page, selector), do: page |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
end

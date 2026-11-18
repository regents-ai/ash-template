defmodule AshTemplateWeb.AgentBudgetTest do
  # Signed agent requests on the API share one budget for each person, after the
  # endpoint's budget for each address, through this site's own endpoint and
  # router (`AshTemplateWeb.Plugs.AgentWallet`):
  # - the agents paired with one person spend one budget of 120 requests a
  #   minute, whichever route each calls, and past it either is refused as an
  #   address past its own budget is, with the seconds to wait;
  # - another person's agent goes on, and so do these agents on the hosted MCP
  #   server, which spends nothing of it;
  # - a forged signature, or an agent acting for no person, spends nothing of it.
  # The sign-in service is stubbed: it vouches for the wallet a request names when
  # the request carries the fixture proof. Each request comes from an address of
  # its own unless a test says otherwise, so only the person's budget runs out.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.RequestRateLimiter
  alias AshTemplate.Actors.System

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    old = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})

    on_exit(fn ->
      case old do
        {:ok, opts} -> Application.put_env(:regent_agents, :req_options, opts)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end
    end)

    Req.Test.stub(RegentAgents.Broker, fn conn ->
      {:ok, body, conn} = read_body(conn)
      headers = Jason.decode!(body)["headers"]

      if headers["x-siwa-signature"] == "fixture-proof" do
        wallet = headers["x-agent-wallet-address"]

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
      else
        conn
        |> put_status(401)
        |> Req.Test.json(%{
          error: %{
            code: "http_signature_invalid",
            message: "Signature invalid",
            hint: "Sign again"
          }
        })
      end
    end)

    # Budgets are counted in whole minutes; requests that might straddle two start
    # in the next one.
    {:ok, %{reset: left}} = RequestRateLimiter.admit({"minute", make_ref()}, 1, 60)
    if left < 5, do: Process.sleep(left * 1000)

    :ok
  end

  test "one person's agents share 120 signed requests a minute on every route, refused past it as an address is" do
    person = person()
    agents = {agent(person), agent(person)}
    other = agent(person())

    # One agent reads its own profile, the other its person's mutes, in turn.
    calls = [fn -> api(elem(agents, 0)) end, fn -> api(elem(agents, 1), "/api/v1/mutes") end]
    answers = calls |> Stream.cycle() |> Enum.take(121) |> Enum.map(& &1.())

    assert Enum.map(answers, & &1.status) == List.duplicate(200, 120) ++ [429]
    refused = List.last(answers)
    assert [wait] = get_resp_header(refused, "retry-after")
    assert String.to_integer(wait) in 1..60
    assert ratelimit(refused) =~ ~s("agent";r=0;)

    # The person's other agent is refused from the same budget.
    assert api(elem(agents, 1), "/api/v1/mutes").status == 429

    # An address past its own budget is refused in the same words.
    from = address()
    for _request <- 1..120, do: conn(:get, "/api/v1/nothing") |> from(from) |> @endpoint.call([])
    by_address = api(other, "/api/v1/agents/me", from: from)
    assert by_address.status == 429 and get_resp_header(by_address, "retry-after") != []
    assert json(by_address) == json(refused)

    # Another person's agent still goes on, and so do these agents on the hosted server.
    assert api(other).status == 200
    assert mcp(elem(agents, 0)).status == 200
  end

  test "a forged signature, or an agent acting for no person, spends nothing of a person's budget" do
    person = person()
    agent = agent(person)
    {gone, pairing} = pair(person)
    :ok = RegentAgents.unpair_agent(pairing, actor: %RegentAgents.Person{privy_user_id: person})

    forged = for _request <- 1..3, do: api(agent, "/api/v1/agents/me", signature: "forged")
    assert Enum.map(forged, & &1.status) == [401, 401, 401]

    # The unpaired agent reads its own profile, and is refused its former person's mutes.
    assert api(gone).status == 200
    assert api(gone, "/api/v1/mutes").status == 403

    answer = api(agent)
    assert answer.status == 200
    assert ratelimit(answer) =~ ~s("agent";r=119;)
  end

  test "the hosted MCP server checks the same signature and spends nothing of the API's budget" do
    agent = agent(person())

    for _call <- 1..3, do: assert(mcp(agent).status == 200)

    answer = api(agent)
    assert answer.status == 200
    assert ratelimit(answer) =~ ~s("agent";r=119;)
  end

  test "a request past the person's budget writes its visit line with the code the answer carries" do
    agent = agent(person())
    for _request <- 1..120, do: api(agent)

    # Visit lines are info; the suite's logger keeps warnings and above.
    Logger.put_module_level(AshTemplateWeb.VisitLog, :info)
    :ok = :logger.add_handler(:agent_budget_test_visits, __MODULE__, %{config: %{test: self()}})

    on_exit(fn ->
      :logger.remove_handler(:agent_budget_test_visits)
      Logger.delete_module_level(AshTemplateWeb.VisitLog)
    end)

    assert api(agent).status == 429
    assert_receive {:visit, %{name: "tool.call", outcome: "too_many_requests"}}
  end

  # A signed GET of `path` by `wallet`, from an address of its own unless `from`
  # names one.
  defp api(wallet, path \\ "/api/v1/agents/me", opts \\ []) do
    conn(:get, path)
    |> from(Keyword.get_lazy(opts, :from, &address/0))
    |> signed(wallet, Keyword.get(opts, :signature, "fixture-proof"))
    |> @endpoint.call([])
  end

  # A signed `tools/list` call to the hosted MCP server.
  defp mcp(wallet) do
    conn(:post, "/mcp", Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}))
    |> from(address())
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
    |> signed(wallet, "fixture-proof")
    |> @endpoint.call([])
  end

  defp signed(conn, wallet, signature) do
    conn
    |> put_req_header("x-siwa-signature", signature)
    |> put_req_header("x-agent-wallet-address", wallet)
  end

  defp from(conn, address), do: Map.put(conn, :remote_ip, address)

  defp address, do: {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)}

  defp ratelimit(conn), do: conn |> get_resp_header("ratelimit") |> Enum.join(", ")

  defp json(conn), do: Jason.decode!(conn.resp_body)

  # A person who has signed in here with a wallet, by their sign-in id.
  defp person do
    did = "did:privy:budget-" <> Ecto.UUID.generate()
    wallet = wallet()
    Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    did
  end

  # A new agent's wallet, paired with `person`.
  defp agent(person), do: person |> pair() |> elem(0)

  # A new agent's wallet and its pairing with `person`, from a code they gave it.
  defp pair(person) do
    agent = wallet()
    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: person})

    {agent,
     RegentAgents.pair_agent!(code.code, "Agent", :codex,
       actor: %RegentAgents.Agent{wallet: agent}
     )}
  end

  # A logger handler that sends each visit line to the test that added it.
  def log(%{meta: %{event: event}}, %{config: %{test: test}}), do: send(test, {:visit, event})
  def log(_event, _config), do: :ok

  defp wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
end

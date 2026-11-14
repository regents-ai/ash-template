defmodule AshTemplateWeb.SiwaSessionTest do
  # The SIWA pages' sign-in at the sign-in service (POST /siwa/session): the
  # browser's Privy pair is traded there, with the session cookie and the forms
  # token, for a control token that stays on this machine, kept for this
  # browser's sign-in while SIWA names the person signed in here, and dropped
  # when the sign-in ends. The service is stood in for.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # The refusals log their fixed reasons; the first test reads its own log.
  @moduletag :capture_log
  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, put_private: 3, put_req_header: 3]

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.SiwaControl
  alias AshTemplate.SiwaControl.Tokens

  @endpoint AshTemplateWeb.Endpoint
  @did "did:privy:siwa-session"
  @wallet "0x" <> String.duplicate("5", 40)
  @pair [{"authorization", "Bearer privy-access"}, {"privy-id-token", "privy-identity"}]

  setup do
    :ets.delete_all_objects(AshTemplate.Accounts.RequestRateLimiter)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "siwa-session",
        privy_user_id: @did,
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)
    topic = SessionAuthority.topic(claim.lineage)
    on_exit(fn -> Tokens.forget(topic) end)

    page =
      build_conn()
      |> Plug.Test.init_test_session(SessionAuthority.session(claim))
      |> get("/auth/csrf")

    %{account: account, topic: topic, page: page, csrf: json_response(page, 200)["csrf_token"]}
  end

  # The service answers each trade with `answer` and says it was asked.
  defp service(answer) do
    test = self()

    Req.Test.stub(SiwaControl, fn conn ->
      send(test, {:asked, Map.new(conn.req_headers)})
      answer.(conn)
    end)
  end

  defp session(did, minutes \\ 15) do
    fn conn ->
      expires_at = DateTime.utc_now() |> DateTime.add(minutes, :minute) |> DateTime.to_iso8601()

      Req.Test.json(conn, %{
        code: "control_session",
        data: %{token: "control-token", expiresAt: expires_at, did: did}
      })
    end
  end

  defp refusal(status, code) do
    &(&1
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{error: %{code: code, message: "refused", hint: nil}}))
  end

  # The browser's trade: the session cookie, the forms token when it has one and
  # the Privy pair. Phoenix's test connection skips the forms token check; this
  # keeps it, as a browser's does.
  defp trade(conn, csrf, headers \\ @pair) do
    conn = conn |> recycle() |> put_private(:plug_skip_csrf_protection, false)
    conn = if csrf, do: put_req_header(conn, "x-csrf-token", csrf), else: conn

    headers
    |> Enum.reduce(conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> post("/siwa/session")
  end

  test "the pair is traded at SIWA, and only this machine keeps the token, for this sign-in until it ends",
       %{account: account, topic: topic, page: page, csrf: csrf} do
    service(session(@did))
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    {traded, log} = with_log(fn -> trade(page, csrf) end)

    assert traded.status == 204
    assert traded.resp_body == ""
    assert get_resp_header(traded, "cache-control") == ["no-store"]
    assert_received {:asked, %{"authorization" => "Bearer privy-access", "privy-id-token" => "privy-identity"}}
    assert Tokens.token(topic, account.id) == {:ok, "control-token"}
    assert Tokens.token(topic, Ecto.UUID.generate()) == :error

    for secret <- ["control-token", "privy-access", "privy-identity"], do: refute(log =~ secret)

    signed_out =
      traded
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", csrf)
      |> delete("/auth/privy/session")

    assert signed_out.status == 200
    assert Tokens.token(topic, account.id) == :error
  end

  test "without the forms token nothing is traded", %{account: account, topic: topic, page: page} do
    service(session(@did))

    assert_error_sent(403, fn -> trade(page, nil) end)
    refute_received {:asked, _headers}
    assert Tokens.token(topic, account.id) == :error
  end

  test "with nobody signed in here nothing is traded" do
    service(session(@did))
    page = get(build_conn(), "/auth/csrf")

    refused = trade(page, json_response(page, 200)["csrf_token"])

    assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    refute_received {:asked, _headers}
  end

  test "no pair, a pair SIWA refuses, another person or a token already ended keeps nothing",
       %{account: account, topic: topic, page: page, csrf: csrf} do
    service(session(@did))
    refused = trade(page, csrf, [])
    assert json_response(refused, 401)["error"]["code"] == "siwa_sign_in_refused"
    refute_received {:asked, _headers}

    for {answer, status, code} <- [
          {refusal(401, "privy_proof_invalid"), 401, "siwa_sign_in_refused"},
          {session("did:privy:someone-else"), 401, "siwa_sign_in_refused"},
          {session(@did, -1), 503, "siwa_unavailable"}
        ] do
      service(answer)
      traded = trade(page, csrf)

      assert json_response(traded, status)["error"]["code"] == code
      refute traded.resp_body =~ "control-token"
      assert Tokens.token(topic, account.id) == :error
    end
  end

  test "SIWA turned off, broken or out of reach is unavailable", %{page: page, csrf: csrf} do
    for answer <- [
          refusal(503, "control_not_configured"),
          refusal(500, "internal_error"),
          &Req.Test.text(&1, "control-token"),
          &Req.Test.transport_error(&1, :econnrefused)
        ] do
      service(answer)
      refused = trade(page, csrf)

      assert json_response(refused, 503)["error"]["code"] == "siwa_unavailable"
      refute refused.resp_body =~ "control-token"
    end
  end

  test "a person trades at most 30 times a minute", %{page: page, csrf: csrf} do
    service(session(@did))

    for _trade <- 1..30, do: assert(trade(page, csrf).status == 204)

    limited = trade(page, csrf)
    assert json_response(limited, 429)["error"]["code"] == "rate_limited"
    assert get_resp_header(limited, "retry-after") == ["60"]
  end
end

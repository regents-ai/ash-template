defmodule AshTemplateWeb.SessionChecksTest do
  # A page reads the sign-in once for its first answer and once as it connects,
  # and again at every navigation and press after that (AshTemplateWeb.Live.Session),
  # so a sign-in revoked while the page is open stops at the person's next one.
  # The revocations here send no disconnect, as a sign-in that ends on another
  # machine of the site would not, so only the page's own check can refuse.
  # Each check reads the sign-in's session row once.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.Activity.Notification
  alias AshTemplate.Actors.Human

  @endpoint AshTemplateWeb.Endpoint
  @wallet "0x" <> String.duplicate("d", 40)
  @signed_out "#account-control [data-account-target='sign-in']"
  @signed_in "#account-control[data-account-wallet='#{@wallet}']"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "session-checks",
        privy_user_id: "did:privy:session-checks",
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)

    ref = make_ref()
    id = {__MODULE__, ref}

    :ok =
      :telemetry.attach(
        id,
        [:ash_template, :repo, :query],
        &__MODULE__.session_read/4,
        {self(), ref}
      )

    on_exit(fn -> :telemetry.detach(id) end)

    %{account: account, claim: claim, reads: ref}
  end

  @doc false
  def session_read(
        _event,
        _measurements,
        %{source: "session_authorities", query: "SELECT" <> _},
        {test, ref}
      ),
      do: send(test, {:session_read, ref})

  def session_read(_event, _measurements, _metadata, _config), do: :ok

  # LiveViewTest connects with the conn's own session as the socket's, as a
  # browser does, once the connection's details are a map.
  defp browser(session) do
    build_conn()
    |> Plug.Conn.put_req_header("accept", "text/html")
    |> Plug.Test.init_test_session(session)
    |> Plug.Conn.put_private(:live_view_connect_info, %{})
  end

  defp reads(ref, count \\ 0) do
    receive do
      {:session_read, ^ref} -> reads(ref, count + 1)
    after
      0 -> count
    end
  end

  test "the first answer and the connected page each read the sign-in once, and every navigation and press after that again",
       %{claim: claim, reads: ref} do
    conn = claim |> SessionAuthority.session() |> browser() |> get("/rooms/general")
    assert reads(ref) == 1

    assert conn
           |> html_response(200)
           |> LazyHTML.from_document()
           |> LazyHTML.query(@signed_in)
           |> Enum.any?()

    {:ok, view, _html} = live(conn)
    assert reads(ref) == 1
    assert has_element?(view, @signed_in)

    render_patch(view, "/notes")
    assert reads(ref) == 1

    render_hook(view, "public_name_saved", %{})
    assert reads(ref) == 1
    assert has_element?(view, @signed_in)
  end

  test "a sign-in revoked before the page connects is refused as it connects", %{claim: claim} do
    conn = claim |> SessionAuthority.session() |> browser() |> get("/rooms/general")
    SessionAuthority.revoke(claim)

    assert {:error, {:redirect, %{to: "/"}}} = live(conn)
  end

  test "a sign-in revoked after the page connected is refused at the next navigation", %{
    claim: claim
  } do
    {:ok, view, _html} =
      claim |> SessionAuthority.session() |> browser() |> live("/rooms/general")

    SessionAuthority.revoke(claim)

    assert {:error, {:redirect, %{to: "/"}}} = render_patch(view, "/notes")
  end

  test "a press after the sign-in was revoked is refused, changes nothing and leaves the page signed out",
       %{account: account, claim: claim} do
    unread =
      Ash.Seed.seed!(Notification, %{
        human_account_id: account.id,
        title: "Mentioned",
        path: "/rooms/general"
      })

    {:ok, view, _html} =
      claim |> SessionAuthority.session() |> browser() |> live("/rooms/general")

    SessionAuthority.revoke(claim)

    render_hook(view, "mark_all_read", %{})

    assert has_element?(view, @signed_out)
    assert %{read_at: nil} = Ash.get!(Notification, unread.id, actor: Human.for_account(account))
  end

  test "a reader who never signed in is shown signed out, and a session row they hold is read once for each answer",
       %{reads: ref} do
    {:bootstrap, unbound} = SessionAuthority.renew(nil)

    for {session, each} <- [{%{}, 0}, {SessionAuthority.session(unbound), 1}] do
      conn = session |> browser() |> get("/rooms/general")
      assert reads(ref) == each

      assert conn
             |> html_response(200)
             |> LazyHTML.from_document()
             |> LazyHTML.query(@signed_out)
             |> Enum.any?()

      {:ok, view, _html} = live(conn)
      assert reads(ref) == each
      assert has_element?(view, @signed_out)
    end
  end
end

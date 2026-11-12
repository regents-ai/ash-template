defmodule AshTemplateWeb.ErrorsAdminTest do
  # The team's pages, /admin/errors and /admin/messages, are for the site's admins
  # only, through the shared owners check (RegentPrivy.Owners) reading the session
  # rows (AshTemplateWeb.ErrorsAdmin): signed out, or signed in as anyone else, the
  # page is not found; an admin opens both, the errors page under its own nonce;
  # and a sign-in that ends while a page is open is sent away on its next press.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.SessionAuthority
  alias AshTemplate.Actors.System
  alias AshTemplateWeb.{ContentSecurityPolicy, ErrorsAdmin}
  alias Phoenix.LiveView.{Lifecycle, Socket}

  @endpoint AshTemplateWeb.Endpoint
  @pages ["/admin/errors", "/admin/messages"]

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end

  test "signed out, or signed in as anyone but an admin, finds no page" do
    {person, _claim, _account} = signed_in()
    put_admins(["did:privy:someone-else"])

    for path <- @pages do
      assert build_conn() |> get(path) |> html_response(404)
      assert person |> get(path) |> html_response(404)
    end
  end

  test "an admin opens both pages, the errors page under its own nonce" do
    {conn, _claim, account} = signed_in()
    put_admins([account.privy_user_id])

    errors = get(conn, "/admin/errors")
    assert html_response(errors, 200)

    assert Plug.Conn.get_resp_header(errors, "content-security-policy") ==
             [ContentSecurityPolicy.errors(errors.assigns.csp_nonce)]

    assert conn |> get("/admin/messages") |> html_response(200)
  end

  # The page's hooks as the router names them for /admin/messages, on the session
  # the page was opened with; /admin/errors has the first alone.
  test "an admin's open page acts as the admin until the sign-in ends, then is sent away on the next press" do
    {conn, claim, account} = signed_in()
    put_admins([account.privy_user_id])
    session = Plug.Conn.get_session(conn)
    socket = %Socket{router: AshTemplateWeb.Router, private: %{lifecycle: %Lifecycle{}}}

    {:cont, socket} = RegentPrivy.Owners.on_mount(ErrorsAdmin, %{}, session, socket)
    {:cont, socket} = ErrorsAdmin.on_mount(:admin, %{}, session, socket)
    assert socket.assigns.admin == %RegentAgents.Person{privy_user_id: account.privy_user_id, role: :admin}
    assert {:cont, _socket} = press(socket)

    SessionAuthority.revoke(claim)

    assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} = press(socket)
  end

  defp press(socket) do
    [%{function: hook}] = socket.private.lifecycle.handle_event
    hook.("press", %{}, socket)
  end

  defp signed_in do
    did = "did:privy:errors-admin-" <> Ecto.UUID.generate()
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)
    {Plug.Test.init_test_session(build_conn(), SessionAuthority.session(claim)), claim, account}
  end

  # The team page's read asks RegentAgents' own admin list too.
  defp put_admins(admins) do
    for app <- [:ash_template, :regent_agents] do
      old = Application.fetch_env(app, :admins)
      Application.put_env(app, :admins, admins)

      on_exit(fn ->
        case old do
          {:ok, value} -> Application.put_env(app, :admins, value)
          :error -> Application.delete_env(app, :admins)
        end
      end)
    end
  end
end

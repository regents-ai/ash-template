defmodule AshTemplateWeb.FirstRenderTest do
  # Regression: pages read the site's own database with start_async, which never
  # runs on the first, unconnected render, so a signed-in page sent "Loading…"
  # and showed its notes or chat only once the page had connected.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.{Chat, Notes}
  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.Actors.Human

  @endpoint AshTemplateWeb.Endpoint
  @wallet "0x" <> String.duplicate("b", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "first-render",
        privy_user_id: "did:privy:first-render",
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)

    conn =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> Plug.Test.init_test_session(SessionAuthority.session(claim))

    %{conn: conn, actor: Human.for_account(account)}
  end

  test "a person's notes are in the first render of Notes", %{conn: conn, actor: actor} do
    {:ok, _note} =
      Notes.create_note(%{title: "Seed list", body: "Plant the pines"}, actor: actor)

    html = conn |> get("/notes") |> html_response(200)

    assert html =~ "Seed list"
    refute html =~ "Loading"
  end

  test "a conversation's messages are in the first render of Chat", %{conn: conn, actor: actor} do
    {:ok, message} = Chat.create_message(%{text: "Where do the pines go?"}, actor: actor)

    html = conn |> get("/chat/#{message.conversation_id}") |> html_response(200)

    assert html =~ "Where do the pines go?"
    refute html =~ "Loading"
  end
end

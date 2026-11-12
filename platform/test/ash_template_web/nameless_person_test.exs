defmodule AshTemplateWeb.NamelessPersonTest do
  # Every wallet is public (Sean, 6 Nov 2026): someone who chose no name shows by
  # their wallet wherever a page names them, and its copy icon copies it in full. A
  # room's author line, a poll's Started by and a private conversation all do.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.{Accounts, Dms, Polls, Rooms}
  alias AshTemplate.Accounts.SessionAuthority
  alias AshTemplate.Actors.{Human, System}

  @endpoint AshTemplateWeb.Endpoint
  @reader "0x" <> String.duplicate("c", 40)
  @nameless "0x" <> String.duplicate("7", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    reader = Accounts.register_verified!("did:privy:nameless-reader", @reader, [@reader], actor: %System{})
    nameless = Accounts.register_verified!("did:privy:nameless", @nameless, [@nameless], actor: %System{})

    post =
      Rooms.post_message!(%{room: "general", body: "Hello from nobody in particular."},
        actor: Human.for_account(nameless),
        context: %{client_key: "nameless-person-test"}
      )

    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, reader.id)

    conn =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> Plug.Test.init_test_session(SessionAuthority.session(claim))

    %{conn: conn, reader: reader, nameless: nameless, post: post}
  end

  test "a room shows its author by their wallet", %{conn: conn} do
    assert @nameless in copies(conn, "/rooms/general")
  end

  test "a poll shows who started it by their wallet", %{conn: conn, nameless: nameless} do
    poll =
      Polls.start_poll!(%{question: "Tea or coffee?", choices: ["Tea", "Coffee"], minutes: 60},
        actor: Human.for_account(nameless)
      )

    assert @nameless in copies(conn, "/polls/#{poll.id}")
  end

  test "a private conversation shows the other person by their wallet", %{
    conn: conn,
    reader: reader,
    post: post
  } do
    conversation = Dms.open_conversation!(post.id, actor: Human.for_account(reader))

    # The list of conversations goes to the sidebar through a portal, a <template>
    # the HTML parser keeps apart, so its copy icon is read from the page's text.
    assert conn |> get("/dms") |> html_response(200) =~ ~s(data-copy-text="#{@nameless}")
    assert @nameless in copies(conn, "/dms/#{conversation.id}")
  end

  # The full address each copy icon on the page copies.
  defp copies(conn, path) do
    conn
    |> get(path)
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("[data-copy-text]")
    |> LazyHTML.attribute("data-copy-text")
  end
end

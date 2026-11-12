defmodule AshTemplateWeb.MessagesPagesTest do
  # The pages around a message left for the site's team:
  # - /agents and the /app home carry the Agent Message dialog for their topic, with a paste-ready
  #   text for each way an agent connects, and the form only for a signed-in person
  #   (test/browser/agent_message.spec.ts leaves one through it);
  # - /admin/messages shows the team every message, newest first, and is the
  #   not-found page for anyone who is not one of the site's admins.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.{Accounts, Messages}
  alias AshTemplate.Accounts.SessionAuthority
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplateWeb.Components.AgentMessage

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    :ok
  end

  # A plain page (/agents) and a live page (the /app home in the shell) place it
  # the same way, each under its own topic.
  for {path, topic, dialog} <- [{"/agents", "agents", "agents-message"}, {"/app", "app", "app-message"}] do
    test "#{path} offers the Agent Message texts to everyone, and the form only to a signed-in person" do
      signed_out = page(build_conn(), unquote(path))

      texts =
        signed_out
        |> LazyHTML.query("##{unquote(dialog)} .agent-message__text pre code")
        |> Enum.map(&LazyHTML.text/1)

      assert texts == Enum.map(AgentMessage.texts(unquote(topic)), & &1.text)
      assert [cli, mcp, webmcp] = texts
      assert cli =~ "messages leave #{unquote(topic)}"
      assert mcp =~ "messages_leave" and webmcp =~ "messages_leave"

      copied =
        signed_out
        |> LazyHTML.query("##{unquote(dialog)} [data-copy-target]")
        |> LazyHTML.attribute("data-copy-target")

      assert length(copied) == 3
      form = "##{unquote(dialog)}-person-form"
      assert Enum.empty?(LazyHTML.query(signed_out, form))

      {conn, _account} = signed_in()
      assert Enum.count(LazyHTML.query(page(conn, unquote(path)), form)) == 1
    end
  end

  test "/admin/messages shows the team every message, and is not found for anyone else" do
    {person, account} = signed_in()
    {:ok, older} = leave(account, "agents", "First")
    {:ok, newer} = leave(account, "watchdog", "Second")

    assert build_conn() |> get("/admin/messages") |> response(404)
    assert person |> get("/admin/messages") |> response(404)

    put_admins([account.privy_user_id])
    page = page(person, "/admin/messages")

    ids = page |> LazyHTML.query("#admin-messages > li") |> LazyHTML.attribute("id")
    assert Enum.take(ids, 2) == ["message-#{newer.id}", "message-#{older.id}"]
    assert LazyHTML.text(page) =~ "Second"
  end

  defp leave(account, topic, body),
    do:
      Messages.leave_message(%{topic: topic, body: body},
        actor: Human.for_account(account),
        context: %{client_key: Ecto.UUID.generate()}
      )

  defp page(conn, path),
    do: conn |> put_req_header("accept", "text/html") |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp signed_in do
    did = "did:privy:messages-page-" <> Ecto.UUID.generate()
    wallet = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
    account = Accounts.register_verified!(did, wallet, [wallet], actor: %System{})
    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)
    {Plug.Test.init_test_session(build_conn(), SessionAuthority.session(claim)), account}
  end

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

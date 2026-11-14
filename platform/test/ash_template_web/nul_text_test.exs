defmodule AshTemplateWeb.NulTextTest do
  # Postgres keeps no NUL character in text. Text a person or an agent sends with
  # one, in a note's title or body, a room message, a direct message, a chat
  # message, a poll's question or choice, or a public name, is refused as any
  # other hidden character is (`RegentFormat.Text`, `RegentFormat.Name`), before
  # anything is written: through the page's form and through the API, each with
  # its ordinary refusal and never a failure, and nothing is saved.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [put_req_header: 3]

  alias AshTemplate.{Accounts, Chat, Dms, Notes, Polls, Rooms}
  alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
  alias AshTemplate.Actors.Human

  @endpoint AshTemplateWeb.Endpoint
  @did "did:privy:nul-text"
  @wallet "0x" <> String.duplicate("d", 40)
  @agent "0x" <> String.duplicate("2", 40)
  @nul "Hello\u0000there"

  setup do
    :ets.delete_all_objects(AshTemplate.Accounts.RequestRateLimiter)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    broker = Application.fetch_env(:regent_agents, :req_options)
    Application.put_env(:regent_agents, :req_options, plug: {Req.Test, RegentAgents.Broker})

    on_exit(fn ->
      case broker do
        {:ok, options} -> Application.put_env(:regent_agents, :req_options, options)
        :error -> Application.delete_env(:regent_agents, :req_options)
      end

      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    # The sign-in service vouches for the paired agent's wallet.
    Req.Test.stub(RegentAgents.Broker, fn conn ->
      Req.Test.json(conn, %{
        code: "http_envelope_valid",
        data: %{
          verified: true,
          walletAddress: @agent,
          agentBook: nil,
          agentRegistration: nil,
          principal: %{
            kind: "wallet",
            wallet_address: @agent,
            chain_id: 8453,
            audience: RegentAgents.Broker.audience()
          }
        }
      })
    end)

    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "nul-text",
        privy_user_id: @did,
        wallet_address: @wallet,
        wallet_addresses: [@wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    code = RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: @did})

    RegentAgents.pair_agent!(code.code, "Fixture", :codex,
      actor: %RegentAgents.Agent{wallet: @agent}
    )

    person = [actor: Human.for_account(account), context: %{client_key: @did}]
    friend_wallet = "0x" <> String.duplicate("f", 40)

    friend =
      Accounts.register_verified!("did:privy:nul-friend", friend_wallet, [friend_wallet],
        actor: %AshTemplate.Actors.System{}
      )

    said =
      Rooms.post_message!(%{room: "general", body: "Hello"},
        actor: Human.for_account(friend),
        context: %{client_key: "nul-friend"}
      )

    %{
      account: account,
      note: Notes.create_note!(%{title: "Seed", body: "Plant"}, person),
      message: Rooms.post_message!(%{room: "general", body: "Hi"}, person),
      conversation: Dms.open_conversation!(said.id, person)
    }
  end

  test "the API refuses each with its ordinary refusal, naming the field, and saves nothing", %{
    account: account,
    note: note,
    message: message,
    conversation: conversation
  } do
    saved = saved()

    for {method, path, body, code, field} <- [
          {:post, "/api/v1/notes", %{title: @nul}, "invalid_note", "title"},
          {:post, "/api/v1/notes", %{title: "Seed", body: @nul}, "invalid_note", "body"},
          {:patch, "/api/v1/notes/#{note.id}", %{title: @nul}, "invalid_note", "title"},
          {:patch, "/api/v1/notes/#{note.id}", %{body: @nul}, "invalid_note", "body"},
          {:post, "/api/v1/rooms/general/messages", %{body: @nul}, "invalid_message", "body"},
          {:patch, "/api/v1/rooms/general/messages/#{message.id}", %{body: @nul},
           "invalid_message", "body"},
          {:post, "/api/v1/dms/#{conversation.id}/messages", %{body: @nul}, "invalid_message",
           "body"},
          {:post, "/api/v1/chat/messages", %{text: @nul}, "invalid_message", "text"},
          {:post, "/api/v1/polls", %{question: @nul, choices: ["Yes", "No"], minutes: 5},
           "invalid_poll", "question"},
          {:post, "/api/v1/polls", %{question: "Plant?", choices: ["Yes", @nul], minutes: 5},
           "invalid_poll", "choices"}
        ] do
      refused = agent(method, path, Map.put(body, :operation_id, Ecto.UUID.generate()))
      assert %{"code" => ^code, "details" => details} = json_response(refused, 422)["error"]
      assert field in Enum.map(details, & &1["field"]), "#{method} #{path}: #{inspect(details)}"
    end

    # The person's own name, set by their agent and from the Account page's form,
    # which sends it with the page's sign-in.
    for refused <- [
          agent(:patch, "/api/v1/profile", %{display_name: @nul}),
          account
          |> signed_in()
          |> put_req_header("accept", "application/json")
          |> put_req_header("content-type", "application/json")
          |> patch("/api/v1/profile", Jason.encode!(%{display_name: @nul}))
        ] do
      assert json_response(refused, 422)["error"]["code"] == "invalid_display_name"
    end

    assert saved() == saved
  end

  test "each page's form marks the field it refused and saves nothing", %{
    account: account,
    conversation: conversation
  } do
    saved = saved()

    for {path, form, params, field} <- [
          {"/notes", "#note-form", %{"note" => %{"title" => @nul}}, "note[title]"},
          {"/notes", "#note-form", %{"note" => %{"title" => "Seed", "body" => @nul}},
           "note[body]"},
          {"/rooms/general", "#room-message-form", %{"message" => %{"body" => @nul}},
           "message[body]"},
          {"/dms/#{conversation.id}", "#dms-message-form", %{"message" => %{"body" => @nul}},
           "message[body]"},
          {"/chat", "#chat-message-form", %{"message" => %{"text" => @nul}}, "message[text]"},
          {"/polls", "#poll-start-form",
           %{"poll" => %{"question" => @nul, "choices_text" => "Yes\nNo"}}, "poll[question]"},
          {"/polls", "#poll-start-form",
           %{"poll" => %{"question" => "Plant?", "choices_text" => "Yes\n" <> @nul}},
           "poll[choices_text]"}
        ] do
      {:ok, view, _html} = account |> signed_in() |> live(path)
      view |> form(form, params) |> render_submit()
      assert has_element?(view, ~s(#{form} [name="#{field}"][aria-invalid="true"])), path
    end

    assert saved() == saved
  end

  # How many of each kind of record the text could have gone into.
  defp saved,
    do:
      for(
        resource <- [Notes.Note, Rooms.Message, Dms.Message, Chat.Message, Polls.Poll],
        do: Ash.count!(resource, authorize?: false)
      )

  # The paired agent's request, signed with its wallet.
  defp agent(method, path, body) do
    build_conn()
    |> put_req_header("x-siwa-signature", "fixture-proof")
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  # The person's browser, signed in here. LiveViewTest connects with the conn's
  # own session as the socket's, as a browser does, once the connection's details
  # are a map.
  defp signed_in(account) do
    {:bootstrap, claim} = SessionAuthority.renew(nil)
    {:ok, :bind, claim} = SessionAuthority.sign_in(claim, account.id)

    build_conn()
    |> put_req_header("accept", "text/html")
    |> Plug.Test.init_test_session(SessionAuthority.session(claim))
    |> Plug.Conn.put_private(:live_view_connect_info, %{})
  end
end

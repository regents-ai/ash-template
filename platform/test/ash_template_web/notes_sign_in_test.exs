defmodule AshTemplateWeb.NotesSignInTest do
  # The notes API answers the person signed in on this site, from its own pages,
  # or an agent they paired (`AshTemplate.SignedToolsTest`). This signs in through
  # the site's own sign-in step, as the browser does, with tokens signed as Privy
  # signs them, then uses the session that step left.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_private: 3, put_req_header: 3]

  @endpoint AshTemplateWeb.Endpoint
  @did "did:privy:notes-session"
  @wallet "0x" <> String.duplicate("6", 40)

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    key = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    privy = Application.fetch_env!(:ash_template, :privy)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)

    Application.put_env(
      :ash_template,
      :privy,
      privy |> Keyword.put(:app_id, "test-app") |> Keyword.put(:verification_key, pem)
    )

    Application.put_env(:ash_template, :app_surfaces, true)

    on_exit(fn ->
      Application.put_env(:ash_template, :privy, privy)
      Application.put_env(:ash_template, :app_surfaces, open?)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    %{key: key}
  end

  test "the person signed in on this site reads and changes their notes, a change only with the forms token",
       %{key: key} do
    {signed_in, token} = sign_in(key)
    id = Ecto.UUID.generate()

    created =
      send_json(signed_in, :post, "/api/v1/notes", %{title: "Groceries", operation_id: id}, token)

    assert json_response(created, 201)["note"]["id"] == id

    assert [%{"id" => ^id}] =
             signed_in
             |> send_json(:post, "/api/v1/notes/list", %{}, token)
             |> json_response(200)
             |> Map.fetch!("notes")

    # A read changes nothing, so it needs no forms token.
    assert signed_in |> recycle() |> get("/api/v1/notes/" <> id) |> json_response(200)

    # Without the forms token a change counts as signed out and changes nothing.
    for {method, path, body} <- [
          {:post, "/api/v1/notes", %{title: "Unsent", operation_id: Ecto.UUID.generate()}},
          {:post, "/api/v1/notes/list", %{}},
          {:patch, "/api/v1/notes/" <> id, %{title: "Unsent"}},
          {:delete, "/api/v1/notes/" <> id, nil}
        ] do
      refused = send_json(signed_in, method, path, body, nil)
      assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    end

    assert signed_in
           |> recycle()
           |> get("/api/v1/notes/" <> id)
           |> json_response(200)
           |> get_in(["note", "title"]) ==
             "Groceries"

    updated = send_json(signed_in, :patch, "/api/v1/notes/" <> id, %{title: "Shopping"}, token)
    assert json_response(updated, 200)["note"]["title"] == "Shopping"

    deleted = send_json(signed_in, :delete, "/api/v1/notes/" <> id, nil, token)
    assert json_response(deleted, 200)["deleted"] == true
    assert signed_in |> recycle() |> get("/api/v1/notes/" <> id) |> json_response(404)
  end

  test "Privy's own tokens are not a sign-in on the notes API, even for a person signed in here",
       %{key: key} do
    {signed_in, token} = sign_in(key)
    id = Ecto.UUID.generate()
    send_json(signed_in, :post, "/api/v1/notes", %{title: "Mine", operation_id: id}, token)
    proof = proof(key)

    for {method, path, body} <- [
          {:post, "/api/v1/notes/list", "{}"},
          {:get, "/api/v1/notes/" <> id, nil},
          {:post, "/api/v1/notes",
           Jason.encode!(%{title: "Unsent", operation_id: Ecto.UUID.generate()})}
        ] do
      refused =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer " <> proof.access)
        |> put_req_header("privy-id-token", proof.identity)
        |> dispatch(@endpoint, method, path, body)

      assert json_response(refused, 401)["error"]["code"] == "authentication_required"
    end

    assert [%{"id" => ^id}] =
             signed_in
             |> send_json(:post, "/api/v1/notes/list", %{}, token)
             |> json_response(200)
             |> Map.fetch!("notes")
  end

  # Phoenix's test connection skips the forms token check; these requests keep it,
  # as a browser's do.
  defp send_json(conn, method, path, body, token) do
    conn =
      conn
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")

    conn = if token, do: put_req_header(conn, "x-csrf-token", token), else: conn
    dispatch(conn, @endpoint, method, path, if(body, do: Jason.encode!(body)))
  end

  # The browser's steps: a fresh session, then Privy's two tokens on the sign-in
  # step, then the forms token the site's pages carry for the session that step left.
  defp sign_in(key) do
    csrf = build_conn() |> get("/auth/csrf")
    proof = proof(key)

    signed_in =
      csrf
      |> recycle()
      |> put_req_header("x-csrf-token", Jason.decode!(csrf.resp_body)["csrf_token"])
      |> put_req_header("authorization", "Bearer " <> proof.access)
      |> put_req_header("privy-id-token", proof.identity)
      |> post("/auth/privy/session")

    assert signed_in.status == 200
    page = signed_in |> recycle() |> get("/auth/csrf")
    {page, json_response(page, 200)["csrf_token"]}
  end

  defp proof(key) do
    now = System.system_time(:second)

    claims = %{
      "iss" => "privy.io",
      "aud" => "test-app",
      "sub" => @did,
      "iat" => now - 1,
      "exp" => now + 600,
      "sid" => @did
    }

    linked = [
      %{
        "type" => "wallet",
        "address" => @wallet,
        "chain_type" => "ethereum",
        "wallet_client_type" => "metamask",
        "lv" => now
      }
    ]

    sign = fn claims ->
      key |> JOSE.JWT.sign(%{"alg" => "ES256"}, claims) |> JOSE.JWS.compact() |> elem(1)
    end

    %{
      access: sign.(claims),
      identity: sign.(Map.put(claims, "linked_accounts", Jason.encode!(linked)))
    }
  end
end

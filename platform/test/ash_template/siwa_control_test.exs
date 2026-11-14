defmodule AshTemplate.SiwaControlTest do
  # The sign-in service's control API (`AshTemplate.SiwaControl`), stood in for
  # here: each answer is the service's data, its refusal or unavailable, nothing
  # is sent twice, and a new site key never prints.
  use ExUnit.Case, async: true

  alias AshTemplate.SiwaControl
  alias AshTemplate.SiwaControl.{Refusal, Secret}

  defp answer(status, body) do
    test = self()

    Req.Test.expect(SiwaControl, fn conn ->
      {:ok, sent, conn} = Plug.Conn.read_body(conn)

      send(test, {:asked, conn.method, conn.request_path, conn.req_headers, sent})
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  defp header(headers, name), do: for({^name, value} <- headers, do: value)

  test "the Privy pair is traded with the access token as the bearer and the identity token beside it" do
    answer(200, %{
      code: "control_session",
      data: %{token: "control-token", expiresAt: "2026-11-14T10:15:00Z", did: "did:privy:a"}
    })

    assert SiwaControl.session(%{access: "privy-access", identity: "privy-identity"}) ==
             {:ok,
              %{"token" => "control-token", "expiresAt" => "2026-11-14T10:15:00Z", "did" => "did:privy:a"}}

    assert_received {:asked, "POST", "/api/control/v1/session", headers, ""}
    assert header(headers, "authorization") == ["Bearer privy-access"]
    assert header(headers, "privy-id-token") == ["privy-identity"]
  end

  test "every other call sends the control token, and a body only as JSON" do
    site = %{"id" => Ecto.UUID.generate(), "name" => "Docs"}
    answer(200, %{code: "site_updated", data: site})

    params = %{"name" => "Docs", "origins" => ["http://localhost:4000"]}
    assert SiwaControl.update_site("control-token", site["id"], params) == {:ok, site}

    path = "/api/control/v1/sites/#{site["id"]}"
    assert_received {:asked, "PATCH", ^path, headers, sent}
    assert header(headers, "authorization") == ["Bearer control-token"]
    assert Jason.decode!(sent) == params
  end

  test "a refusal keeps its status, code, message, hint and each field's reasons" do
    answer(422, %{
      error: %{
        code: "control_fields_invalid",
        message: "some fields are not valid",
        hint: "Correct each field.",
        fields: %{origins: ["lists an origin twice"], name: [7]}
      }
    })

    assert SiwaControl.create_site("control-token", %{}) ==
             {:error,
              %Refusal{
                status: 422,
                code: "control_fields_invalid",
                message: "some fields are not valid",
                hint: "Correct each field.",
                fields: %{"origins" => ["lists an origin twice"]}
              }}
  end

  test "an answer in no shape the service gives, or none at all, is unavailable and asked once" do
    for status <- [200, 502] do
      Req.Test.expect(SiwaControl, &(&1 |> Plug.Conn.put_status(status) |> Req.Test.html("<p>")))
      assert SiwaControl.list_sites("control-token") == {:error, :unavailable}
    end

    answer(200, %{sites: []})
    assert SiwaControl.list_sites("control-token") == {:error, :unavailable}

    Req.Test.expect(SiwaControl, &Req.Test.transport_error(&1, :econnrefused))
    assert SiwaControl.archive_site("control-token", Ecto.UUID.generate()) == {:error, :unavailable}

    Req.Test.expect(SiwaControl, &Req.Test.transport_error(&1, :timeout))
    assert SiwaControl.create_site_key("control-token", Ecto.UUID.generate()) == {:error, :unavailable}

    Req.Test.verify!(SiwaControl)
  end

  test "a new key comes once, as a secret no inspection shows" do
    key = "siwa_sk_test_" <> String.duplicate("k", 43)
    made = %{id: Ecto.UUID.generate(), prefix: binary_part(key, 0, 19), createdAt: "2026-11-14T10:00:00Z"}
    answer(201, %{code: "site_key_created", data: Map.put(made, :key, key)})

    assert {:ok, %{"key" => %Secret{value: ^key}} = created} =
             SiwaControl.create_site_key("control-token", Ecto.UUID.generate())

    refute inspect(created) =~ key

    answer(201, %{code: "site_key_created", data: made})
    assert SiwaControl.create_site_key("control-token", Ecto.UUID.generate()) == {:error, :unavailable}
  end
end

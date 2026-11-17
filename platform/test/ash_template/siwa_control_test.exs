defmodule AshTemplate.SiwaControlTest do
  # The sign-in service's control API (`AshTemplate.SiwaControl`), stood in for
  # here: each answer is the service's data, its refusal or unavailable, nothing
  # is sent twice, a period's fee stays exact, a new site key never prints and
  # Stripe's pages come only as https addresses.
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

  test "a proof check is sent with no body and answers the site after it" do
    proof = %{
      "state" => "unverified",
      "token" => "siwa_site_" <> String.duplicate("a", 32),
      "fileUrls" => ["https://acme.example/.well-known/siwa-site.txt"],
      "checkedAt" => "2026-11-14T07:02:10Z",
      "verifiedAt" => nil,
      "failureReason" => "not_found",
      "failedOrigin" => "https://acme.example"
    }

    site = %{"id" => Ecto.UUID.generate(), "environment" => "production", "originProof" => proof}
    answer(200, %{code: "site_proof_checked", data: site})

    assert SiwaControl.check_site_proof("control-token", site["id"]) == {:ok, site}

    path = "/api/control/v1/sites/#{site["id"]}/proof"
    assert_received {:asked, "POST", ^path, headers, ""}
    assert header(headers, "authorization") == ["Bearer control-token"]
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

  test "a billing period's fee comes exact, as a Decimal, and a fee in any other shape is unavailable" do
    usage = %{
      periodStartsAt: "2026-11-01T00:00:00Z",
      periodEndsAt: "2026-12-01T00:00:00Z",
      activeAgents: 1_001,
      includedAgents: 1_000,
      feeCents: "9909.9",
      capCents: nil,
      maxAgents: nil
    }

    billing = %{configured: true, subscriptionStatus: "active"}
    account = %{did: "did:privy:a", customer: nil, usage: usage, billing: billing}

    answer(200, %{code: "account", data: account})
    assert {:ok, %{"usage" => %{"feeCents" => fee}, "billing" => billed}} = SiwaControl.account("control-token")
    assert Decimal.equal?(fee, Decimal.new("9909.9"))
    assert billed == %{"configured" => true, "subscriptionStatus" => "active"}

    answer(200, %{code: "account", data: %{account | usage: nil}})
    assert {:ok, %{"usage" => nil}} = SiwaControl.account("control-token")

    for fee <- [9909.9, "9909.90", "9,909.9"] do
      answer(200, %{code: "account", data: %{account | usage: %{usage | feeCents: fee}}})
      assert SiwaControl.account("control-token") == {:error, :unavailable}
    end
  end

  test "Subscribe and Manage send only the address to come back to, and answer Stripe's https page" do
    return_url = "https://acme.example/siwa/billing"

    for {call, path, code, url} <- [
          {&SiwaControl.checkout/2, "/api/control/v1/billing/checkout", "billing_checkout",
           "https://checkout.stripe.com/c/pay/cs_test_a1"},
          {&SiwaControl.portal/2, "/api/control/v1/billing/portal", "billing_portal",
           "https://billing.stripe.com/p/session/test_a1"}
        ] do
      answer(200, %{code: code, data: %{url: url}})
      assert call.("control-token", return_url) == {:ok, %{"url" => url}}
      assert_received {:asked, "POST", ^path, headers, sent}
      assert header(headers, "authorization") == ["Bearer control-token"]
      assert Jason.decode!(sent) == %{"returnUrl" => return_url}

      # No page, or one that isn't https, is not Stripe's page.
      for data <- [%{}, %{url: nil}, %{url: "http://checkout.stripe.com/c/pay/cs_test_a1"}] do
        answer(200, %{code: code, data: data})
        assert call.("control-token", return_url) == {:error, :unavailable}
      end

      # Billing off at SIWA is its refusal, like any other.
      answer(503, %{error: %{code: "billing_not_configured", message: "billing is off"}})

      assert {:error, %Refusal{status: 503, code: "billing_not_configured"}} =
               call.("control-token", return_url)
    end
  end

  test "invoices are asked a page at a time, after the cursor of the page before" do
    test = self()

    page = %{
      invoices: [
        %{
          id: "in_2",
          createdAt: "2026-12-01T09:31:02Z",
          periodStartsAt: "2026-11-01T09:30:00Z",
          periodEndsAt: "2026-12-01T09:30:00Z",
          totalCents: 24_750,
          status: "paid",
          hostedUrl: "https://invoice.stripe.com/i/acct_1/test_a1",
          agents: 2_500
        }
      ],
      next: "in_2"
    }

    for _page <- 1..2 do
      Req.Test.expect(SiwaControl, fn conn ->
        send(test, {:asked, conn.method, conn.request_path, conn.query_string})
        Req.Test.json(conn, %{code: "invoices", data: page})
      end)
    end

    assert {:ok, %{"invoices" => [%{"totalCents" => 24_750}], "next" => "in_2"}} =
             SiwaControl.list_invoices("control-token", nil)

    assert_received {:asked, "GET", "/api/control/v1/billing/invoices", ""}

    assert {:ok, _page} = SiwaControl.list_invoices("control-token", "in_2")
    assert_received {:asked, "GET", "/api/control/v1/billing/invoices", "after=in_2"}
  end

  test "a cap is sent in whole cents, and null removes it" do
    customer = %{id: Ecto.UUID.generate(), name: "Acme", capCents: 50_000}

    for cap <- [50_000, nil] do
      answer(200, %{code: "cap_updated", data: %{customer: %{customer | capCents: cap}, usage: nil}})
      assert {:ok, %{"customer" => %{"capCents" => ^cap}}} = SiwaControl.set_cap("control-token", cap)
      assert_received {:asked, "PUT", "/api/control/v1/cap", _headers, sent}
      assert Jason.decode!(sent) == %{"capCents" => cap}
    end
  end

  test "the period's agents are asked a page at a time, after the cursor of the page before" do
    test = self()

    page = %{
      agents: [
        %{
          subject: "eip155:8453:0x" <> String.duplicate("1", 40),
          firstVerifiedAt: "2026-11-14T10:00:00Z",
          firstSiteId: Ecto.UUID.generate()
        }
      ],
      next: "cursor-1"
    }

    for _page <- 1..2 do
      Req.Test.expect(SiwaControl, fn conn ->
        send(test, {:asked, conn.method, conn.request_path, conn.query_string})
        Req.Test.json(conn, %{code: "agents", data: page})
      end)
    end

    assert {:ok, %{"agents" => [_agent], "next" => "cursor-1"}} =
             SiwaControl.list_agents("control-token", nil)

    assert_received {:asked, "GET", "/api/control/v1/agents", ""}

    assert {:ok, _page} = SiwaControl.list_agents("control-token", "cursor-1")
    assert_received {:asked, "GET", "/api/control/v1/agents", "after=cursor-1"}
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

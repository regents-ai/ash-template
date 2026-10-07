defmodule AshTemplateWeb.Plugs.AgentWallet do
  @moduledoc """
  Signs in an agent from its signed request. The agent signs in once with the
  shared sign-in service's agent client (https://siwa.regents.sh/skill.md) and
  signs every request after that over its exact method, path and body. The service
  checks the signature and the sign-in (`Siwa.AgentAuthPlug`), so only a wallet
  it vouches for becomes the actor, as itself (`AshTemplate.Actors.Agent`).
  Cookies grant nothing here. Every refusal answers
  `{"error": {"code", "message", "hint"}}`, with the service's own words when it
  refused.
  """

  @behaviour Plug
  @behaviour Siwa.AgentAuthPlug.Client
  @behaviour Siwa.AgentAuthPlug.Hooks

  import Plug.Conn

  alias AshTemplate.Actors.{Agent, System}
  alias AshTemplate.Agents

  @audience "ash-template"
  @headers ~w(x-siwa-receipt signature signature-input x-key-id x-timestamp x-agent-wallet-address x-agent-chain-id content-digest)
  @hint "Sign in with the agent client at https://siwa.regents.sh/skill.md, then send the request again."

  # Refusals made here, before or after the sign-in service answered.
  @refusals %{
    duplicate_proof: {401, "A signature header was sent more than once.", @hint},
    unsupported_query: {401, "A signed request here takes no query string.", @hint},
    missing_signed_body:
      {401, "Send the body as JSON, signed with the rest of the request.", @hint},
    unsupported_principal: {401, "Only a wallet signed in to this site can do this.", @hint},
    siwa_request_failed:
      {503, "The sign-in service could not be reached.", "Try again in a moment."},
    agent_unavailable:
      {503, "The agent could not be signed in right now.", "Try again in a moment."}
  }

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    Siwa.AgentAuthPlug.call(conn, client: __MODULE__, hooks: __MODULE__, audience: @audience)
  end

  @impl Siwa.AgentAuthPlug.Hooks
  def before_verify(conn, _headers) do
    repeated = conn.req_headers |> Enum.map(&elem(&1, 0)) |> Enum.frequencies()

    cond do
      Enum.any?(@headers, &(Map.get(repeated, &1, 0) > 1)) -> refused(:duplicate_proof)
      conn.query_string != "" -> refused(:unsupported_query)
      not signed_json?(conn) -> refused(:missing_signed_body)
      true -> {:ok, nil}
    end
  end

  @impl Siwa.AgentAuthPlug.Client
  def verify_http_request(payload, _opts) do
    Siwa.AgentAuthPlug.BrokerClient.verify_http_request(
      Map.update!(payload, "headers", &Map.take(&1, @headers)),
      http: __MODULE__,
      base_url: Application.fetch_env!(:ash_template, :agent_sign_in)[:broker_url],
      audience: @audience,
      connect_timeout_ms: 3_000,
      receive_timeout_ms: 5_000
    )
  end

  # Checking a signed request uses up its one-time nonce, so it is never retried
  # or redirected.
  def request(opts), do: Req.request(Keyword.merge(opts, retry: false, redirect: false))

  @impl Siwa.AgentAuthPlug.Hooks
  def accept(
        conn,
        %{
          "verified" => true,
          "walletAddress" => address,
          "agentBook" => book,
          "principal" => %{
            "kind" => "wallet",
            "wallet_address" => address,
            "audience" => @audience
          }
        },
        _context
      ) do
    case Agents.sign_in_agent(address, world_id(book), actor: %System{}) do
      {:ok, agent} -> {:ok, assign(conn, :actor, Agent.for_agent(agent))}
      {:error, _error} -> refused(:agent_unavailable)
    end
  end

  def accept(_conn, _data, _context), do: refused(:unsupported_principal)

  # The person World ID says stands behind the wallet, once the wallet has accepted
  # them; null otherwise, which clears what an earlier request kept.
  defp world_id(%{"humanId" => human_id, "agentCount" => count}),
    do: %{world_id_human_id: human_id, world_id_agent_count: count}

  defp world_id(nil), do: %{world_id_human_id: nil, world_id_agent_count: nil}

  @impl Siwa.AgentAuthPlug.Hooks
  def deny(conn, %{reason: reason}) when is_map_key(@refusals, reason) do
    {status, message, hint} = Map.fetch!(@refusals, reason)
    refuse(conn, status, %{code: to_string(reason), message: message, hint: hint})
  end

  # The sign-in service refused: its status and its own words.
  def deny(conn, %{siwa_status: status} = failure) do
    body = %{
      code: failure[:siwa_code] || "sign_in_refused",
      message: failure[:siwa_message] || "The request's wallet signature was not accepted.",
      hint: failure[:siwa_hint] || @hint
    }

    refuse(conn, status, body)
  end

  defp refuse(conn, status, body) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: body})
    |> halt()
  end

  defp signed_json?(%{assigns: %{raw_body: body}, private: %{signed_body_complete: true}} = conn)
       when is_binary(body) do
    case get_req_header(conn, "content-type") do
      [type] -> type |> String.split(";", parts: 2) |> hd() |> String.trim() == "application/json"
      _other -> false
    end
  end

  defp signed_json?(_conn), do: false

  defp refused(reason), do: {:error, %{reason: reason, source: :agent_wallet}}
end

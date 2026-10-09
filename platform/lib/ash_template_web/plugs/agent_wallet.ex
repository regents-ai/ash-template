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
  @behaviour Siwa.AgentAuthPlug.Hooks

  import Plug.Conn

  alias AshTemplate.{Accounts, Agents}
  alias AshTemplate.Actors.{Agent, System}

  @hint "Sign in with the agent client at https://siwa.regents.sh/skill.md, then send the request again."

  # Refusals made here or by the shared plug, before or after the sign-in service
  # answered.
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
    Siwa.AgentAuthPlug.call(conn,
      client: RegentAgents.Broker,
      hooks: __MODULE__,
      audience: RegentAgents.Broker.audience()
    )
  end

  # The shared plug has already refused a query string and a body it did not
  # capture whole. A body sent here is JSON.
  @impl Siwa.AgentAuthPlug.Hooks
  def before_verify(conn, _headers) do
    if is_map_key(conn.assigns, :raw_body) and not json?(conn),
      do: refused(:missing_signed_body),
      else: {:ok, nil}
  end

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
            "chain_id" => 8453,
            "audience" => audience
          }
        },
        _context
      ) do
    if audience == RegentAgents.Broker.audience(),
      do: sign_in(conn, address, book),
      else: refused(:unsupported_principal)
  end

  def accept(_conn, _data, _context), do: refused(:unsupported_principal)

  defp sign_in(conn, address, book) do
    with {:ok, agent} <- Agents.sign_in_agent(address, actor: %System{}),
         {:ok, agent} <- record_backing(agent, book),
         {:ok, actor} <- actor(agent) do
      {:ok, assign(conn, :actor, actor)}
    else
      {:error, _error} -> refused(:agent_unavailable)
    end
  end

  defp actor(agent) do
    case RegentAgents.Authority.resolve(AshTemplate.Repo, agent.wallet_address) do
      {:ok, pairing} -> paired(agent, pairing)
      {:error, :not_paired} -> {:ok, Agent.for_agent(agent)}
      {:error, error} -> {:error, error}
    end
  end

  defp paired(agent, pairing) do
    case Accounts.get_by_privy_did(pairing.privy_user_id, actor: %System{}) do
      {:ok, %{} = account} -> {:ok, Agent.paired(agent, account, pairing)}
      {:ok, nil} -> {:ok, Agent.for_agent(agent, :person_not_here)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  The refusal code for an agent that acts as itself where only an agent acting as
  its person may go, naming what it is missing.
  """
  def not_person_code(%Agent{pairing: :none}), do: "agent_not_paired"
  def not_person_code(%Agent{pairing: :person_not_here}), do: "person_not_here"

  # The person World ID says stands behind the wallet, once the wallet has accepted
  # them. Null names nobody and changes nothing: the link, once made, stays.
  defp record_backing(agent, %{"humanId" => human_id, "agentCount" => count}),
    do: Agents.record_backing(agent, human_id, count, actor: %System{})

  defp record_backing(agent, nil), do: {:ok, agent}

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

  defp json?(conn) do
    case get_req_header(conn, "content-type") do
      [type] -> type |> String.split(";", parts: 2) |> hd() |> String.trim() == "application/json"
      _other -> false
    end
  end

  defp refused(reason), do: {:error, %{reason: reason, source: :agent_wallet}}
end

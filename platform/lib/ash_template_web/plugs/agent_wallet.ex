defmodule AshTemplateWeb.Plugs.AgentWallet do
  @moduledoc """
  Signs in an agent from its signed request. The agent signs in once
  (`regents auth login --site ash-template`, or its own SIWA signer) and
  signs every request after that over its exact method, path and body. The service
  checks the signature and the sign-in (`Siwa.AgentAuthPlug`), so only a wallet
  it vouches for becomes the actor. An agent whose wallet signs in to an account
  owns it and acts as its owner (`AshTemplate.Actors.Human.owner/2`); any other
  agent acts as itself (`AshTemplate.Actors.Agent`), for the person it is paired
  with when it is. Cookies grant nothing here. The account or pairing is checked
  again just before the answer leaves, so a change during the request never sends
  the former account's data. Every refusal answers
  `{"error": {"code", "message", "hint"}}`, with the service's own words when it
  refused.
  """

  @behaviour Plug
  @behaviour Siwa.AgentAuthPlug.Hooks

  import Plug.Conn

  require Logger

  alias AshTemplate.{Accounts, Agents}
  alias AshTemplate.Accounts.AgentAccount
  alias AshTemplate.Actors.{Agent, Human, System}
  alias AshTemplateWeb.UnexpectedFailure

  @hint "Sign in with regents auth login --site ash-template (how: https://template.regents.sh/agents.md), then send the request again."

  # What an agent that is not acting as its person is told, the same at every door.
  @not_person %{
    "agent_not_paired" =>
      {403, "This agent is not paired with an account.",
       "Ask your person to sign in on this site and pair you with Pair New Agent on their Account page, or open your own account with POST /api/v1/agent/account, then send the request again. Help: https://patchbay.help/errors/agent_not_paired"},
    "person_not_here" =>
      {403, "The person this agent is paired with hasn't signed in on this site yet.",
       "Ask your person to sign in on this site once, then send the request again. Help: https://patchbay.help/errors/person_not_here"}
  }
  @unavailable %{
    code: "unavailable",
    message: "The paired account could not be read.",
    hint: "Try again in a moment."
  }

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

  @doc """
  Whether `actor` acts for an account: its owner, or an agent its person paired.
  Every door that acts for a person admits exactly these.
  """
  defguard acts_for_account(actor)
           when is_struct(actor, Human) or
                  (is_struct(actor, Agent) and :erlang.map_get(:pairing, actor) == :active)

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
         {:ok, actor} <- agent |> with_backing(book) |> actor() do
      {:ok, conn |> assign(:actor, actor) |> recheck_before_send(actor, agent.wallet_address)}
    else
      {:error, error} ->
        UnexpectedFailure.log(conn, error)
        refused(:agent_unavailable)
    end
  end

  defp actor(agent) do
    case AgentAccount.owned(agent.wallet_address) do
      {:ok, %{} = account} -> {:ok, Human.owner(account, agent)}
      {:ok, nil} -> delegated(agent)
      {:error, error} -> {:error, error}
    end
  end

  defp delegated(agent) do
    case RegentAgents.Authority.resolve(AshTemplate.Repo, agent.wallet_address) do
      {:ok, pairing} -> paired(agent, pairing)
      {:error, :not_paired} -> {:ok, Agent.for_agent(agent)}
      {:error, error} -> {:error, error}
    end
  end

  defp paired(agent, pairing) do
    case Accounts.get_by_privy_did(pairing.privy_user_id, actor: %System{}) do
      {:ok, %{} = account} -> with_profile(agent, account, pairing)
      {:ok, nil} -> {:ok, Agent.for_agent(agent, :person_not_here)}
      {:error, error} -> {:error, error}
    end
  end

  defp with_profile(agent, account, pairing) do
    app_id = :ash_template |> Application.fetch_env!(:privy) |> Keyword.fetch!(:app_id)

    with {:ok, profile_id} <- RegentIdentity.profile_id(app_id, pairing.privy_user_id),
         do: {:ok, Agent.paired(agent, account, pairing, profile_id)}
  end

  defp recheck_before_send(conn, actor, wallet) when acts_for_account(actor),
    do: register_before_send(conn, &recheck(&1, actor, wallet))

  defp recheck_before_send(conn, _actor, _wallet), do: conn

  # The account was read before the request ran. Before anything is sent, the
  # wallet must still sign in to the same account, as for a pairing below.
  defp recheck(conn, %Human{} = owner, wallet) do
    case AgentAccount.owned(wallet) do
      {:ok, %{id: id}} when id == owner.human_account_id -> conn
      {:ok, _other} -> replace(conn, "agent_not_paired")
      {:error, error} when conn.status in 200..299 -> unavailable(conn, error)
      {:error, _error} -> conn
    end
  end

  # The request ran after the pairing was read. Before anything is sent, the
  # wallet's current pairing must still be this one, with the same person;
  # otherwise the answer is replaced, so an unpairing or a new pairing during
  # the request never sends the former person's data.
  defp recheck(conn, %Agent{} = actor, _wallet) do
    case RegentAgents.Authority.resolve(AshTemplate.Repo, actor.wallet_address) do
      {:ok, %{id: id, privy_user_id: person}}
      when id == actor.pairing_id and person == actor.privy_user_id ->
        conn

      {:error, :not_paired} ->
        replace(conn, "agent_not_paired")

      {:ok, _other_pairing} ->
        replace(conn, "agent_not_paired")

      {:error, error} when conn.status in 200..299 ->
        unavailable(conn, error)

      {:error, _error} ->
        conn
    end
  end

  defp unavailable(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> replace(503, @unavailable)

  defp replace(conn, code) do
    {status, message, hint} = Map.fetch!(@not_person, code)
    replace(conn, status, %{code: code, message: message, hint: hint})
  end

  defp replace(conn, status, body) do
    %{conn | status: status, resp_body: Jason.encode_to_iodata!(%{error: body})}
    |> put_resp_content_type("application/json")
  end

  @doc """
  The `{status, message, hint}` of each refusal `AshTemplate.Agents.NotPaired`
  names, for a door's own table of refusals.
  """
  def not_person_refusals, do: @not_person

  # The person World ID says stands behind the wallet, once the wallet has accepted
  # them. Null names nobody and changes nothing: the link, once made, stays.
  #
  # Nothing here decides what the agent may do, so a save that fails never fails
  # the request: the agent goes on as it was read, and its next request saves the
  # same thing.
  defp with_backing(agent, %{"humanId" => human_id, "agentCount" => count}) do
    case Agents.record_backing(agent, human_id, count, actor: %System{}) do
      {:ok, agent} -> agent
      {:error, error} -> backing_not_saved(agent, error)
    end
  end

  defp with_backing(agent, nil), do: agent

  # Logged by the agent's id and the kind of failure alone: the wallet address
  # beside a World ID person would tie the two together in the log, and the
  # failure's words can hold the person's number.
  defp backing_not_saved(agent, error) do
    Logger.warning(
      "Saving the World ID person of agent #{agent.id} failed: #{inspect(failure_kinds(error))}"
    )

    agent
  end

  defp failure_kinds(%{errors: [_ | _] = errors}), do: Enum.map(errors, & &1.__struct__)
  defp failure_kinds(error), do: [error.__struct__]

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

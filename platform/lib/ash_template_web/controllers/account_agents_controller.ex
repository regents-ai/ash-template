defmodule AshTemplateWeb.AccountAgentsController do
  @moduledoc """
  The owner's controls over the agents paired with its account, as the Account
  page has them (`AshTemplateWeb.AgentsPanel`, `AshTemplateWeb.PairingBox`): list
  them, make a pairing code, rename or unpair one, and read where one has been
  active. Only an agent that opened its own account
  (`AshTemplateWeb.AgentAccountController`) reaches them, acting as its owner;
  a paired agent is refused, so one agent never pairs more agents for its person
  or changes another. Every request needs per-request SIWA proof.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Human
  alias AshTemplate.Agents.ActivityReading
  alias AshTemplate.Limits
  alias AshTemplateWeb.UnexpectedFailure
  alias RegentAgents.{Harness, HumanBacking, PairedAgent, PairingMessage, Person}

  plug :owner

  @errors %{
    "not_account_owner" =>
      {403, "Only an agent that opened its own account can manage the agents paired with it.",
       "An agent your person paired can't change their agents: your person does that on their Account page. An agent with no account opens its own with account_open first."},
    "agent_not_found" =>
      {404, "There is no agent paired with your account with that id.",
       "List your account's agents and use an id from there."},
    "invalid_name" =>
      {422, "That name can't be used.",
       "Send a name of 1 to 80 characters with no hidden characters: no control, line-break, text-direction or zero-width characters, except a zero-width joiner between two visible characters, as in an emoji."},
    "activity_unavailable" =>
      {503, "This agent's activity could not be read right now.", "Try again in a moment."},
    "agents_unavailable" =>
      {503, "Your agents could not be reached right now.", "Try again in a moment."}
  }

  def index(conn, _params) do
    case RegentAgents.list_my_agents(actor: person(conn)) do
      {:ok, agents} -> json(conn, %{agents: Enum.map(agents, &present/1)})
      {:error, error} -> unavailable(conn, error)
    end
  end

  # One code at a time, with the message to hand the agent on `harness`. Codes
  # made before keep working until they expire.
  def issue_code(conn, _params) do
    with {:ok, harness} <- harness(conn.body_params),
         :ok <- Limits.spend_until(:pairing_code, {:owner, conn.assigns.actor.human_account_id}),
         {:ok, code} <- RegentAgents.issue_pairing_code(actor: person(conn)) do
      message = PairingMessage.text(code.code, AshTemplateWeb.Endpoint.url(), harness)

      json(conn, %{
        pairing_code: %{code: code.code, expires_at: code.expires_at, message: message}
      })
    else
      :harness_unknown ->
        harness_unknown(conn)

      {:limited, seconds} ->
        pairing_codes_limited(conn, seconds)

      {:error, error} ->
        unavailable(conn, error)
    end
  end

  def rename(conn, %{"id" => id}) do
    with {:ok, agent} <- my_agent(conn, id),
         {:ok, name} <- name(conn.body_params),
         {:ok, %PairedAgent{} = agent} <-
           RegentAgents.rename_agent(agent, name, actor: person(conn)) do
      json(conn, %{agent: present(agent)})
    else
      :not_found -> refuse(conn, "agent_not_found")
      :invalid_name -> refuse(conn, "invalid_name")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_found")
      {:error, %Ash.Error.Invalid{} = error} -> name_refused(conn, error)
      {:unavailable, error} -> unavailable(conn, error)
      {:error, error} -> unavailable(conn, error)
    end
  end

  def unpair(conn, %{"id" => id}) do
    with {:ok, agent} <- my_agent(conn, id),
         :ok <- RegentAgents.unpair_agent(agent, actor: person(conn)) do
      json(conn, %{unpaired: true})
    else
      :not_found -> refuse(conn, "agent_not_found")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_found")
      {:unavailable, error} -> unavailable(conn, error)
      {:error, error} -> unavailable(conn, error)
    end
  end

  # The same reading the Account page shows, kept on this machine for five minutes.
  def activity(conn, %{"id" => id}) do
    with {:ok, agent} <- my_agent(conn, id),
         {:ok, reading} <- ActivityReading.read(agent) do
      json(conn, %{activity: %{days: Enum.map(reading.days, &day/1), listing: reading.listing}})
    else
      :not_found -> refuse(conn, "agent_not_found")
      {:unavailable, error} -> unavailable(conn, error)
      {:error, _reason} -> refuse(conn, "activity_unavailable")
    end
  end

  defp my_agent(conn, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %PairedAgent{} = agent} <- RegentAgents.get_my_agent(id, actor: person(conn)) do
      {:ok, agent}
    else
      :error -> :not_found
      {:ok, nil} -> :not_found
      {:error, error} -> {:unavailable, error}
    end
  end

  # The owner's Privy user names its agents, as the person's does on the page.
  # Only the owner has one here: a paired agent's actor carries its person's.
  defp person(%{assigns: %{actor: %Human{privy_user_id: id}}}), do: %Person{privy_user_id: id}

  defp harness(%{"harness" => value} = body) when map_size(body) == 1 and is_binary(value) do
    with {:ok, harness} <- Harness.match(value),
         true <- harness in Harness.offered() do
      {:ok, harness}
    else
      _not_offered -> :harness_unknown
    end
  end

  defp harness(_body), do: :harness_unknown

  defp name(%{"name" => name} = body) when map_size(body) == 1 and is_binary(name),
    do: {:ok, name}

  defp name(_body), do: :invalid_name

  defp name_refused(conn, %{errors: errors} = error) do
    if Enum.any?(errors, &match?(%{field: :name}, &1)),
      do: refuse(conn, "invalid_name"),
      else: unavailable(conn, error)
  end

  defp present(agent) do
    %{
      id: agent.id,
      name: agent.name,
      harness: agent.harness,
      wallet_address: agent.wallet,
      human_backed: HumanBacking.describe(agent).human_backed,
      paired_at: agent.paired_at,
      last_contact_at: agent.last_contact_at
    }
  end

  defp day(line),
    do: %{
      site: line.site,
      day: line.day,
      first_seen_at: line.first_seen_at,
      last_seen_at: line.last_seen_at
    }

  defp owner(%{assigns: %{actor: %Human{}}} = conn, _opts),
    do: put_resp_header(conn, "cache-control", "no-store")

  # Any other agent: pairing, or a person signing in here, never opens these.
  defp owner(conn, _opts), do: conn |> refuse("not_account_owner") |> halt()

  defp harness_unknown(conn) do
    harnesses = Enum.map_join(Harness.offered(), ", ", &Atom.to_string/1)

    conn
    |> put_status(422)
    |> json(%{
      error: %{
        code: "harness_unknown",
        message: "That harness is not one we know.",
        hint: "Send harness alone, one of: #{harnesses}. Send other if the agent's is not listed."
      }
    })
  end

  # Its words count the codes from the allowance itself, so the two never differ.
  defp pairing_codes_limited(conn, seconds) do
    limit = Limits.allowance(:pairing_code)[:limit]

    conn
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> put_status(429)
    |> json(%{
      error: %{
        code: "pairing_codes_limited",
        message: "You have made #{limit} pairing codes this hour.",
        hint:
          "Wait the number of seconds in Retry-After, then ask again. Codes you made still work until they expire."
      }
    })
  end

  defp unavailable(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("agents_unavailable")

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end

defmodule AshTemplate.Actors.Persister do
  @moduledoc """
  Carries a signed-in person, or the agent they paired acting for them, into a
  job, so the job acts as them: the assistant's reply reads only that person's
  conversation, and a note's label question counts against that person's share
  of the day's questions.
  """

  use AshOban.ActorPersister

  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Agents.ForPerson

  @agent_fields ~w(agent_id wallet_address name human_account_id privy_user_id pairing_id)a

  def store(%Human{human_account_id: id, person: person}),
    do: %{"type" => "human", "human_account_id" => id, "person" => person}

  def store(%Agent{pairing: :active} = agent),
    do:
      agent
      |> Map.take(@agent_fields)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{"type" => "agent", "person" => agent.person})

  def lookup(%{"type" => "human", "human_account_id" => id, "person" => person}),
    do: {:ok, %Human{human_account_id: id, person: person(person)}}

  # The job acts for the person only while the agent still does as it runs
  # (`ForPerson.still/1`). Otherwise it runs as the agent itself, which no job
  # lets act for anyone, so it ends as it would for an agent never paired.
  def lookup(%{"type" => "agent", "person" => person} = stored) do
    fields = for field <- @agent_fields, do: {field, Map.fetch!(stored, to_string(field))}
    common = [acting_agent_id: stored["agent_id"], pairing: :active, person: person(person)]
    agent = struct!(Agent, common ++ fields)

    case ForPerson.still(agent) do
      :ok -> {:ok, agent}
      {:error, :not_paired} -> {:ok, as_itself(agent, :none)}
      {:error, :person_not_here} -> {:ok, as_itself(agent, :person_not_here)}
      {:error, error} -> {:error, error}
    end
  end

  defp as_itself(agent, pairing),
    do:
      Agent.for_agent(
        %{id: agent.agent_id, wallet_address: agent.wallet_address, name: agent.name},
        pairing
      )

  # A job's arguments come back with their keys as text.
  defp person(%{"name" => name, "wallet" => wallet, "ens_name" => ens_name}),
    do: %{name: name, wallet: wallet, ens_name: ens_name}
end

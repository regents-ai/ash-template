defmodule AshTemplate.Chat.ActorPersister do
  @moduledoc """
  Carries the person who sent a chat message, or the agent they paired that
  sent it for them, into the job that writes the assistant's reply, so the
  reply reads only that person's conversation.
  """

  use AshOban.ActorPersister

  alias AshTemplate.Actors.{Agent, Human}

  @agent_fields ~w(agent_id wallet_address name human_account_id privy_user_id pairing_id)a

  def store(%Human{human_account_id: id, name: name}),
    do: %{"type" => "human", "human_account_id" => id, "name" => name}

  # The job's reads check the pairing again (`RegentAgents.Checks.Paired`), so an
  # agent unpaired before its reply is written reads nothing.
  def store(%Agent{pairing: :active} = agent),
    do:
      agent
      |> Map.take(@agent_fields)
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("type", "agent")

  def lookup(%{"type" => "human", "human_account_id" => id, "name" => name}),
    do: {:ok, %Human{human_account_id: id, name: name}}

  def lookup(%{"type" => "agent"} = stored) do
    fields = for field <- @agent_fields, do: {field, Map.fetch!(stored, to_string(field))}
    {:ok, struct!(Agent, [{:acting_agent_id, stored["agent_id"]}, {:pairing, :active} | fields])}
  end
end

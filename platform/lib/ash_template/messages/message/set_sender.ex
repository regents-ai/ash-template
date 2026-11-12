defmodule AshTemplate.Messages.Message.SetSender do
  @moduledoc """
  Makes the actor the message's sender: a signed-in person, with the agent acting
  for them if one is; or a signed agent, with its person once paired. Nothing a
  caller sends can name the sender.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.{Agent, Human}

  @impl true
  def change(changeset, _opts, %{actor: %Human{} = human}) do
    changeset
    |> Ash.Changeset.force_change_attributes(
      human_account_id: human.human_account_id,
      agent_id: human.acting_agent_id
    )
    |> sender(human.person)
  end

  def change(changeset, _opts, %{actor: %Agent{} = agent}) do
    changeset
    |> Ash.Changeset.force_change_attributes(
      human_account_id: if(agent.pairing == :active, do: agent.human_account_id),
      agent_id: agent.agent_id
    )
    |> sender(%{name: agent.name, wallet: agent.wallet_address, ens_name: nil})
  end

  # Anyone else is refused by the action's policy.
  def change(changeset, _opts, _context), do: changeset

  # How others see the sender as they leave it (`AshTemplate.Messages.Message.sender/1`).
  defp sender(changeset, person) do
    Ash.Changeset.force_change_attributes(changeset,
      sender_name: person.name,
      sender_wallet: person.wallet,
      sender_ens_name: person.ens_name
    )
  end
end

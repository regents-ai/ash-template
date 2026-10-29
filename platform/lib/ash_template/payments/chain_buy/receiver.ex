defmodule AshTemplate.Payments.ChainBuy.Receiver do
  @moduledoc """
  What is bought goes to a wallet of the buyer's own: one the person's
  sign-in verified, or, for an agent, the agent's own wallet.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, %{actor: actor}) do
    receiver =
      changeset |> Ash.Changeset.get_attribute(:receiver) |> to_string() |> String.downcase()

    if receiver in own(actor),
      do: :ok,
      else: {:error, field: :receiver, message: "must be one of your own wallets"}
  end

  defp own(%{role: :person, wallets: wallets}), do: Enum.map(wallets, &String.downcase/1)

  defp own(%{role: :agent, agent_address: address}) when is_binary(address),
    do: [String.downcase(address)]

  defp own(_actor), do: []
end

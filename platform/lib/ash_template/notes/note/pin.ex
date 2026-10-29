defmodule AshTemplate.Notes.Note.Pin do
  @moduledoc """
  Pins a note to the top of its writer's notes. When an agent pins it, the pin
  costs its person one Regent Credit, taken within the limits they set for that
  agent: held before the pin is saved and charged once it is, both inside the
  pin's transaction, so a refused hold pins nothing and a pin that rolls back
  takes nothing.

  The note is read again under a row lock first, so a note already pinned stays
  as it is and costs nothing, and two pins at once pay once. The hold is named
  by the note and the agent's `operation_id`, so a retry never pays twice. Each
  new pin is a new press with its own `operation_id`: one that already paid for
  an earlier pin of this note is refused and pins nothing.
  """

  use Ash.Resource.Change

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Credits

  @price Decimal.new(1)

  @doc "What an agent's pin of an unpinned note costs its person, in Credits."
  @spec price() :: Decimal.t()
  def price, do: @price

  @doc """
  What pinning `note` costs `actor`, in Credits: the price for an agent acting for
  its person, and nothing for a note already pinned or for the account's owner.
  """
  @spec cost(struct(), struct()) :: Decimal.t()
  def cost(%{pinned_at: nil}, %Agent{}), do: @price
  def cost(_note, _actor), do: Decimal.new(0)

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn
      %{data: %{pinned_at: nil}} = changeset ->
        changeset
        |> Ash.Changeset.force_change_attribute(:pinned_at, DateTime.utc_now())
        |> pay(actor)

      changeset ->
        changeset
    end)
  end

  defp pay(changeset, %Agent{} = agent) do
    key = "note-pin:#{changeset.data.id}:#{Ash.Changeset.get_argument(changeset, :operation_id)}"

    case RegentCredits.hold(key, agent.privy_user_id, @price, "note_pin", actor: spender(agent)) do
      {:ok, %{status: :held}} ->
        Ash.Changeset.after_action(changeset, fn _changeset, note -> charge(key, note) end)

      {:ok, _earlier_pin} ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidArgument.exception(
            field: :operation_id,
            message: "already paid for an earlier pin of this note; send a new operation_id"
          )
        )

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp pay(changeset, _person), do: changeset

  defp charge(key, note) do
    with {:ok, _hold} <- RegentCredits.charge(key, actor: Credits.site_actor()),
         do: {:ok, note}
  end

  defp spender(agent),
    do:
      RegentCredits.Actor.agent(
        agent.privy_user_id,
        agent.wallet_address,
        AshTemplate.site(),
        agent.pairing_id
      )
end

defmodule AshTemplate.Payments.NotePin do
  @moduledoc """
  A paired agent pinning one of its person's notes pays for the pin: 1 USDC
  from its own wallet, settled through x402, or 1 of its person's Credits,
  within the limits the person set for it. Either way the money ends in the
  Regents wallet this site names (`:payments_wallet_address`), so the terms
  accept Credits.

  The terms are frozen for one note. Once the payment settles, the note is
  pinned in the same transaction that marks the payment applied. Pinning is
  the same whenever it runs, so a resumed payment pins the note once.
  """

  @behaviour RegentPayments.Offer

  alias AshTemplate.Actors.Agent
  alias AshTemplate.Notes
  alias RegentPayments.AgentAuthority

  @price_atomic 1_000_000

  @doc "What a pin costs, in millionths of a USDC or a Credit."
  @spec price_atomic() :: pos_integer()
  def price_atomic, do: @price_atomic

  @doc "The Regents wallet pins are paid into, or nil while this site names none."
  @spec pay_to() :: String.t() | nil
  def pay_to, do: Application.get_env(:ash_template, :payments_wallet_address)

  @impl true
  def kind, do: :note_pin

  @impl true
  def target_type, do: :note

  @impl true
  def payer?(%Agent{pairing: :active, beneficiary_profile_id: profile}), do: is_binary(profile)
  def payer?(_actor), do: false

  @impl true
  def freeze(%{note_id: note_id}, actor) do
    case Notes.get_my_note(note_id, actor: actor) do
      {:ok, %{} = note} ->
        {:ok,
         %{
           amount_atomic: @price_atomic,
           pay_to_address: pay_to(),
           target_id: note.id,
           payload: %{"note_id" => note.id},
           recipient_snapshot: [%{"wallet_address" => pay_to()}],
           effect_summary: "Pins your person's note \"#{note.title}\" to the top of their notes.",
           credits: :accepted
         }}

      {:ok, nil} ->
        {:error,
         Ash.Error.Changes.InvalidArgument.exception(
           field: :note_id,
           message: "is not one of your person's notes"
         )}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def carry_out(intent, _receipt, actor, _context) do
    if AgentAuthority.completion_for?(actor, intent, kind()) do
      with {:ok, _pinned} <- Notes.pin_note(intent.target_id), do: {:ok, :complete}
    else
      {:error, :not_this_payment}
    end
  end

  @impl true
  def resumes?, do: true
end

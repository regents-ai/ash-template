defmodule AshTemplate.Notes.PinBeingPaidTest do
  # A note cannot be deleted while a pin for it is on offer or paid and not yet
  # applied (`AshTemplate.Notes.Note.PinBeingPaid`), so nobody pays for a pin that
  # has no note left to pin. Every other state of a pin payment lets the delete
  # through: applied, expired, failed, or terms that ran out unpaid.
  use ExUnit.Case, async: false

  alias AshTemplate.{Accounts, Notes}
  alias AshTemplate.Actors.{Human, System}
  alias AshTemplate.Notes.Note.PinBeingPaid
  alias AshTemplate.Payments.NotePin
  alias RegentPayments.PaymentIntent

  @soon 600
  @past -600

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    wallet = "0x" <> String.duplicate("9", 40)

    account =
      Accounts.register_verified!("did:privy:pin-being-paid", wallet, [wallet], actor: %System{})

    %{person: [actor: Human.for_account(account), context: %{client_key: "pin-being-paid"}]}
  end

  for {status, expires_in, kept?} <- [
        {:prepared, @soon, true},
        {:payment_required, @soon, true},
        {:settlement_pending, @soon, true},
        {:settlement_pending, @past, true},
        {:settled, @soon, true},
        {:settled, @past, true},
        {:prepared, @past, false},
        {:payment_required, @past, false},
        {:applied, @soon, false},
        {:expired, @past, false},
        {:failed, @soon, false}
      ] do
    @tag status: status, expires_in: expires_in, kept?: kept?
    test "a pin #{status}, its terms ending in #{expires_in} s: the note #{if kept?, do: "stays", else: "can be deleted"}",
         %{person: person, status: status, expires_in: expires_in, kept?: kept?} do
      note = Notes.create_note!(%{title: "Seed list"}, person)
      pin(note, status, expires_in)

      if kept? do
        assert {:error, %Ash.Error.Invalid{errors: [%PinBeingPaid.Refused{}]}} =
                 Notes.destroy_note(note, person)

        assert {:ok, %{id: _}} = Notes.get_my_note(note.id, person)
      else
        assert :ok = Notes.destroy_note(note, person)
        assert {:ok, nil} = Notes.get_my_note(note.id, person)
      end
    end
  end

  test "a pin being paid for one note leaves the person's other notes free to delete", %{
    person: person
  } do
    paid_for = Notes.create_note!(%{title: "Pinned soon"}, person)
    other = Notes.create_note!(%{title: "Not this one"}, person)
    pin(paid_for, :settlement_pending, @soon)

    assert :ok = Notes.destroy_note(other, person)
  end

  # The payment row as the shared payments library leaves it at each step,
  # written past its actions: only that library moves a payment on.
  defp pin(note, status, expires_in) do
    Ash.Seed.seed!(PaymentIntent, %{
      site: RegentPayments.site(),
      kind: NotePin.kind(),
      actor_profile_id: Ecto.UUID.generate(),
      target_type: NotePin.target_type(),
      target_id: note.id,
      amount_atomic: NotePin.price_atomic(),
      asset: "USDC",
      network: "eip155:8453",
      payload: %{"note_id" => note.id},
      payload_digest: String.duplicate("a", 64),
      recipient_snapshot: [],
      effect_summary: "Pins a note.",
      status: status,
      expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
    })
  end
end

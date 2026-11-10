defmodule AshTemplate.Notes.Note.PinBeingPaid do
  @moduledoc """
  Refuses to delete a note while a pin for it is on offer or paid and not yet
  applied (`AshTemplate.Payments.NotePin`), so nobody pays for a pin that has no
  note left to pin.

  It runs inside the delete's transaction, after the note's row is locked. Pin
  terms are chosen under that same lock
  (`AshTemplateWeb.PairedAgentController`), so of a delete and a pin asked for at
  once, one sees the other: the delete is refused, or the pin finds no note.
  Terms nobody paid stop counting when they run out.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Payments.NotePin
  alias RegentPayments.PaymentIntent

  defmodule Refused do
    @moduledoc "A note delete refused because a pin for the note is being paid for."
    use Splode.Error, fields: [], class: :invalid

    def message(_error), do: "A pin for this note is being paid for"
  end

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case being_paid?(changeset.data.id) do
        {:ok, false} -> changeset
        {:ok, true} -> Ash.Changeset.add_error(changeset, Refused.exception([]))
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  # Asked for the site, not for whoever is deleting: the payer may be another of
  # the person's agents, whose payments the deleter cannot read. Only yes or no
  # leaves this function.
  defp being_paid?(note_id) do
    PaymentIntent
    |> Ash.Query.filter(kind == ^NotePin.kind() and target_type == ^NotePin.target_type())
    |> Ash.Query.filter(target_id == ^note_id)
    |> Ash.Query.filter(
      status in [:settlement_pending, :settled] or
        (status in [:prepared, :payment_required] and expires_at > now())
    )
    |> Ash.exists(authorize?: false)
  end
end

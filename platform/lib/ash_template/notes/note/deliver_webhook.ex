defmodule AshTemplate.Notes.Note.DeliverWebhook do
  @moduledoc """
  Posts the save its job was queued for, before the note is written.

  The call to the other side happens before the update and outside any
  transaction. A failed call fails the action, so the job retries with backoff;
  a 429 snoozes the job for as long as the other side asked; an address taken
  away since the save cancels it.
  """

  use Ash.Resource.Change

  alias AshOban.Errors.{CancelJob, SnoozeJob}
  alias AshTemplate.Notes.Note
  alias AshTemplate.Notes.Webhook

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case deliver(changeset) do
        :ok ->
          changeset

        {:snooze, seconds} ->
          Ash.Changeset.add_error(changeset, SnoozeJob.exception(snooze_for: seconds))

        {:cancel, reason} ->
          Ash.Changeset.add_error(changeset, CancelJob.exception(reason: reason))

        {:error, reason} ->
          Ash.Changeset.add_error(changeset, reason)
      end
    end)
  end

  defp deliver(changeset) do
    args = get_in(changeset.context, [:ash_oban, :job, Access.key(:args)]) || %{}
    pairing_id = args["pairing_id"]

    cond do
      args["authority_version"] != 1 ->
        {:cancel, :legacy_authority_requires_review}

      pairing_id && not RegentAgents.Authority.active_episode?(AshTemplate.Repo, pairing_id) ->
        {:cancel, :pairing_revoked}

      true ->
        case Webhook.address() do
          nil -> {:cancel, :no_address}
          url -> Webhook.deliver(url, changeset.data.id, Note.job_revision(changeset))
        end
    end
  end
end

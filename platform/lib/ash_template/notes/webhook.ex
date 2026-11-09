defmodule AshTemplate.Notes.Webhook do
  @moduledoc """
  Tells the site owner's outside address that a note was saved: the change that
  posts the save a note's `:send_webhook` job was queued for.

  The address is the server setting `ASH_TEMPLATE_NOTES_WEBHOOK_URL`; with none
  set, saving a note queues nothing. Each save is posted once as JSON, carrying
  only which note and which save it was, never the note's text:

      {"event": "note.saved", "note_id": "…", "revision": 3}

  The `webhook-id` header is the same for every attempt at one save, so the
  receiving side can drop a repeat.

  The call to the other side happens before the note is written and outside any
  transaction. A failed call fails the action, so the job retries with backoff;
  a 429 snoozes the job for as long as the other side asked; an address taken
  away since the save cancels it.
  """

  use Ash.Resource.Change

  alias Ash.Error.Unknown.UnknownError
  alias AshOban.Errors.{CancelJob, SnoozeJob}
  alias AshTemplate.Notes.Note

  @doc "The address saved notes are posted to, or nil when none is set."
  @spec address() :: String.t() | nil
  def address, do: Application.get_env(:ash_template, :notes_webhook_url)

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

        # A server fault, so a job that runs out of attempts reaches the error page.
        {:error, reason} ->
          Ash.Changeset.add_error(
            changeset,
            UnknownError.exception(error: "The note's webhook was not delivered: #{reason}")
          )
      end
    end)
  end

  defp deliver(changeset) do
    args = get_in(changeset.context, [:ash_oban, :job, Access.key(:args)]) || %{}
    pairing_id = args["pairing_id"]

    if pairing_id && not RegentAgents.Authority.active_episode?(AshTemplate.Repo, pairing_id) do
      {:cancel, :pairing_revoked}
    else
      case address() do
        nil -> {:cancel, :no_address}
        url -> post(url, changeset.data.id, Note.job_revision(changeset))
      end
    end
  end

  # `:ok` for any 2xx answer, `{:snooze, seconds}` when the other side asks for a
  # pause with 429, and `{:error, reason}` for anything else.
  defp post(url, note_id, revision) do
    case Req.post(url,
           json: %{event: "note.saved", note_id: note_id, revision: revision},
           headers: [{"webhook-id", "#{note_id}:#{revision}"}],
           retry: false,
           redirect: false,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: 429} = response} -> {:snooze, retry_after(response)}
      {:ok, %{status: status}} -> {:error, "the address answered #{status}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp retry_after(response) do
    with [value | _] <- Req.Response.get_header(response, "retry-after"),
         {seconds, ""} when seconds > 0 <- Integer.parse(value) do
      seconds
    else
      _no_seconds -> 60
    end
  end
end

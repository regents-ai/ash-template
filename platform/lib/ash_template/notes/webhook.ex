defmodule AshTemplate.Notes.Webhook do
  @moduledoc """
  Tells the site owner's outside address that a note was saved.

  The address is the server setting `ASH_TEMPLATE_NOTES_WEBHOOK_URL`; with none
  set, saving a note queues nothing. Each save is posted once as JSON, carrying
  only which note and which save it was, never the note's text:

      {"event": "note.saved", "note_id": "…", "revision": 3}

  The `webhook-id` header is the same for every attempt at one save, so the
  receiving side can drop a repeat.
  """

  @doc "The address saved notes are posted to, or nil when none is set."
  @spec address() :: String.t() | nil
  def address, do: Application.get_env(:ash_template, :notes_webhook_url)

  @doc """
  Posts save `revision` of the note with `note_id` to `url`.

  Returns `:ok` for any 2xx answer, `{:snooze, seconds}` when the other side asks
  for a pause with 429, and `{:error, reason}` for anything else.
  """
  @spec deliver(String.t(), Ecto.UUID.t(), pos_integer()) ::
          :ok | {:snooze, pos_integer()} | {:error, String.t()}
  def deliver(url, note_id, revision) do
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

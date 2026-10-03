defmodule AshTemplate.Notes.Note.WebhookAddressSet do
  @moduledoc "Holds when the site owner has set an address for saved notes."

  use Ash.Resource.Validation

  alias AshTemplate.Notes.Webhook

  @impl true
  def validate(_changeset, _opts, _context) do
    if Webhook.address(), do: :ok, else: {:error, message: "no address is set for saved notes"}
  end

  @impl true
  def atomic(changeset, opts, context), do: validate(changeset, opts, context)
end

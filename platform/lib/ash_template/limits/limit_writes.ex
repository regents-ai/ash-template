defmodule AshTemplate.Limits.LimitWrites do
  @moduledoc """
  Holds each writer to the `:allowance` named in `AshTemplate.Limits`, and, with
  `:address_allowance`, the client address the write came from as well, which
  the caller passes as `context: %{client_key: key}` (`AshTemplateWeb.ClientAddress`).
  A write counts when it is saved, not while it is typed, so checking a draft
  never uses the allowance. The count runs before the transaction opens, from the
  actor and the context the caller gave, so a refused write never holds a
  database connection; an update that uses it sets `require_atomic? false`.
  `:message` replaces the words a writer past the allowance sees, for an
  allowance counted over a day. The refusal carries the seconds left of the
  window as `retry_after` among its `vars`, for an answer that says when to try
  again.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Limits

  @quickly "You're going quickly. Wait a moment and try again."

  @impl true
  def init(opts) do
    if Keyword.has_key?(opts, :allowance) and Keyword.has_key?(opts, :field),
      do: {:ok, opts},
      else: {:error, "LimitWrites takes :allowance and :field"}
  end

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    Ash.Changeset.before_transaction(changeset, fn changeset ->
      case spend(changeset, opts, actor) do
        :ok ->
          changeset

        {:limited, seconds} ->
          Ash.Changeset.add_error(
            changeset,
            InvalidAttribute.exception(
              field: opts[:field],
              message: Keyword.get(opts, :message, @quickly),
              vars: [retry_after: seconds]
            )
          )
      end
    end)
  end

  defp spend(changeset, opts, actor) do
    with :ok <- Limits.spend_until(opts[:allowance], writer(actor)),
         do: spend_address(changeset, opts[:address_allowance])
  end

  # Who an actor's writing counts against: the person, or the agent.
  defp writer(%Human{human_account_id: id}), do: {:human, id}
  defp writer(%Agent{pairing: :active, human_account_id: id}), do: {:human, id}
  defp writer(%Agent{agent_id: id}), do: {:agent, id}

  defp spend_address(_changeset, nil), do: :ok

  defp spend_address(%{context: %{client_key: key}}, allowance),
    do: Limits.spend_until(allowance, key)
end

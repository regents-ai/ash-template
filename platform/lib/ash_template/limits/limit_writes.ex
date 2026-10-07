defmodule AshTemplate.Limits.LimitWrites do
  @moduledoc """
  Holds each writer to the `:allowance` named in `AshTemplate.Limits`, and, with
  `:address_allowance`, the client address the write came from as well, which
  the caller passes as `context: %{client_key: key}` (`AshTemplateWeb.ClientAddress`).
  A write counts when it is saved, not while it is typed, so checking a draft
  never uses the allowance. The count runs before the statement, so an update
  that uses it sets `require_atomic? false`.
  """

  use Ash.Resource.Change

  alias AshTemplate.Limits

  @impl true
  def init(opts) do
    if Keyword.has_key?(opts, :allowance) and Keyword.has_key?(opts, :field),
      do: {:ok, opts},
      else: {:error, "LimitWrites takes :allowance and :field"}
  end

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if admitted?(changeset, opts, actor),
        do: changeset,
        else:
          Ash.Changeset.add_error(changeset,
            field: opts[:field],
            message: "You're going quickly. Wait a moment and try again."
          )
    end)
  end

  defp admitted?(changeset, opts, actor) do
    Limits.spend(opts[:allowance], Limits.writer(actor)) == :ok and
      address_admitted?(changeset, opts[:address_allowance])
  end

  defp address_admitted?(_changeset, nil), do: true

  defp address_admitted?(%{context: %{client_key: key}}, allowance),
    do: Limits.spend(allowance, key) == :ok
end

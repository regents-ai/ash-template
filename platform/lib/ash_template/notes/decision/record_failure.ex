defmodule AshTemplate.Notes.Decision.RecordFailure do
  @moduledoc "Records why the decision's last attempt to ask Jev failed."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context),
    do: Ash.Changeset.force_change_attributes(changeset, failed(changeset))

  @impl true
  def atomic(changeset, _opts, _context), do: {:atomic, failed(changeset)}

  defp failed(changeset) do
    %{state: :failed, failure: changeset |> Ash.Changeset.get_argument(:error) |> describe()}
  end

  # The last attempt's errors, without the bread crumbs and stack traces of
  # their full message.
  defp describe(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.fetch!(:errors)
    |> Enum.map_join("; ", &summary/1)
    |> String.slice(0, 500)
  end

  defp summary(%{message: message}) when is_binary(message), do: message
  defp summary(error), do: Exception.message(error)
end

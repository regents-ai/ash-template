defmodule AshTemplate.Notes.Decision.RateOnce do
  @moduledoc """
  A chosen label can be rated once. Checked inside the `UPDATE`, so the second
  of two racing ratings is refused and the row changes once.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case changeset.data do
      %{state: state} when state != :answered -> {:error, error(:state, state, unrated())}
      %{report: report} when not is_nil(report) -> {:error, error(:report, report, rated())}
      _decision -> :ok
    end
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    [
      {:atomic, [:state], expr(state != :answered),
       expr(
         error(Ash.Error.Changes.InvalidAttribute, %{
           field: :state,
           value: state,
           message: ^unrated()
         })
       )},
      {:atomic, [:report], expr(not is_nil(report)),
       expr(
         error(Ash.Error.Changes.InvalidAttribute, %{
           field: :report,
           value: report,
           message: ^rated()
         })
       )}
    ]
  end

  defp error(field, value, message),
    do: Ash.Error.Changes.InvalidAttribute.exception(field: field, value: value, message: message)

  defp unrated, do: "only a chosen label can be rated"
  defp rated, do: "this label has already been rated"
end

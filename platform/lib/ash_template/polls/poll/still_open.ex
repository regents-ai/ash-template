defmodule AshTemplate.Polls.Poll.StillOpen do
  @moduledoc """
  A vote is counted only while its poll is open. Checked inside the `UPDATE`
  that counts it, so a vote that reaches the row after the poll's close or its
  end is turned away, with the whole vote.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if AshTemplate.Polls.open?(changeset.data), do: :ok, else: {:error, closed()}
  end

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:ended_at, :closes_at], expr(not is_nil(ended_at) or closes_at <= now()),
     expr(
       error(Ash.Error.Changes.InvalidAttribute, %{
         field: :poll_id,
         value: id,
         message: ^message()
       })
     )}
  end

  defp closed,
    do: Ash.Error.Changes.InvalidAttribute.exception(field: :poll_id, message: message())

  defp message, do: "This poll has closed."
end

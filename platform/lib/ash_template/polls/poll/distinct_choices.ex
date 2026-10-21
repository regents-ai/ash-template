defmodule AshTemplate.Polls.Poll.DistinctChoices do
  @moduledoc """
  Each of a poll's choices is text you can see, and no two are the same, so a
  vote names exactly one.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    choices = Ash.Changeset.get_attribute(changeset, :choices) || []

    cond do
      not Enum.all?(choices, &Regex.match?(RegentFormat.Name.pattern(), &1)) ->
        {:error, field: :choices, message: "Use letters, numbers and marks you can see."}

      length(Enum.uniq(choices)) != length(choices) ->
        {:error, field: :choices, message: "Give each choice different words."}

      true ->
        :ok
    end
  end
end

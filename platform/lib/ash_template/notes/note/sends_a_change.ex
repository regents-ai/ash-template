defmodule AshTemplate.Notes.Note.SendsAChange do
  @moduledoc """
  A note's change sends its title, its text or both. Text sent empty clears it;
  a change that sends neither changes nothing, so it is refused and never saves
  the note again.
  """

  use Ash.Resource.Validation

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(input, _opts, _context) do
    if Enum.any?(
         [:title, :body],
         &match?({:ok, _value}, Ash.ActionInput.fetch_argument(input, &1))
       ),
       do: :ok,
       else: {:error, fields: [:title, :body], message: "Send title, body or both."}
  end
end

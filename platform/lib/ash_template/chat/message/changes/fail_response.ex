defmodule AshTemplate.Chat.Message.Changes.FailResponse do
  @moduledoc """
  Ends the reply to a person's message whose reply job failed for good: the part
  already written, or a new reply, becomes a line saying so. Without it the page
  would show "The assistant is writing…" forever.
  """

  use Ash.Resource.Change

  alias AshTemplate.Chat.Message.Changes.Respond

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn _changeset, message ->
      %{response: response} = Ash.load!(message, :response, Ash.Context.to_opts(context))
      Respond.save_failed(message, reply_id(response))
      {:ok, message}
    end)
  end

  defp reply_id(nil), do: Ash.UUIDv7.generate()
  defp reply_id(response), do: response.id
end

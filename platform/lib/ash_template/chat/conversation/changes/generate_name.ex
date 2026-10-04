defmodule AshTemplate.Chat.Conversation.Changes.GenerateName do
  @moduledoc """
  Names a conversation from its opening messages, in the job its
  `:name_conversation` trigger queues. The model is the free stand-in
  (`AshTemplate.Chat.StandIn`), which streams, so the name is read from the
  finished stream.
  """

  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_transaction(changeset, &name(&1, context))

  defp name(changeset, context) do
    prompt = [
      Context.system("""
      Provide a short name for the current conversation.
      2-8 words, preferring more succinct names.
      RESPOND WITH ONLY THE NEW CONVERSATION NAME.
      """)
      | changeset.data |> opening_messages(context) |> Enum.map(&prompt_message/1)
    ]

    case ReqLLM.stream_text(%{provider: :stand_in, id: "title"}, prompt) do
      {:ok, response} ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :title,
          ReqLLM.StreamResponse.text(response)
        )

      {:error, error} ->
        {:error, error}
    end
  end

  defp opening_messages(conversation, context) do
    AshTemplate.Chat.Message
    |> Ash.Query.filter(conversation_id == ^conversation.id)
    |> Ash.Query.limit(10)
    |> Ash.Query.select([:text, :source])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(scope: context)
  end

  defp prompt_message(%{source: :agent, text: text}), do: Context.assistant(text)
  defp prompt_message(%{text: text}), do: Context.user(text)
end

defmodule AshTemplate.Chat.Message.Changes.Respond do
  @moduledoc """
  Writes the assistant's reply to a person's message, saving and publishing it
  as it streams in, then queues naming the conversation. Runs in the job the
  message's `:respond` trigger queues. The model is the free stand-in
  (`AshTemplate.Chat.StandIn`).
  """

  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  @empty_reply %{text: "", tool_calls: [], tool_results: [], stream_error: nil}

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_transaction(changeset, &respond(&1, context))

  defp respond(changeset, context) do
    message = changeset.data
    reply_id = Ash.UUIDv7.generate()

    prompt = [
      Context.system("""
      You are a helpful chat bot.
      Your job is to use the tools at your disposal to assist the user.
      """)
      | message |> history(context) |> Enum.map(&prompt_message/1)
    ]

    prompt
    |> AshAi.ToolLoop.stream(
      otp_app: :ash_template,
      tools: true,
      model: %{provider: :stand_in, id: "reply"},
      actor: context.actor,
      tenant: context.tenant,
      context: Map.new(Ash.Context.to_opts(context))
    )
    |> Enum.reduce(@empty_reply, &collect(&1, &2, message, reply_id))
    |> save_reply(message, reply_id)

    name_conversation(message, context)
    changeset
  end

  defp history(message, context) do
    AshTemplate.Chat.Message
    |> Ash.Query.filter(conversation_id == ^message.conversation_id)
    |> Ash.Query.filter(id != ^message.id)
    |> Ash.Query.select([:text, :source, :tool_calls, :tool_results])
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(scope: context)
    |> Enum.concat([%{source: :user, text: message.text}])
  end

  # Historical tool call replay can break provider request validation for prior call IDs.
  # Keep replay text-only; current turn tool usage is handled by AshAi.ToolLoop.
  defp prompt_message(%{source: :agent, text: text}), do: Context.assistant(text || "")
  defp prompt_message(%{source: :user, text: text}), do: Context.user(text || "")

  # Each piece of the reply is saved the moment it arrives, which publishes it to
  # every page that has the conversation open: that is how the reply streams.
  defp collect({:content, content}, reply, _message, _reply_id) when content in [nil, ""],
    do: reply

  defp collect({:content, content}, reply, message, reply_id) do
    save(message, reply_id, %{text: content})
    %{reply | text: reply.text <> content}
  end

  defp collect({:tool_call, tool_call}, reply, _message, _reply_id),
    do: %{reply | tool_calls: reply.tool_calls ++ [tool_call]}

  defp collect({:tool_result, %{id: id, result: result}}, reply, _message, _reply_id),
    do: %{reply | tool_results: reply.tool_results ++ [tool_result(id, result)]}

  defp collect({:error, reason}, reply, _message, _reply_id), do: %{reply | stream_error: reason}
  defp collect(_event, reply, _message, _reply_id), do: reply

  defp save_reply(@empty_reply, _message, _reply_id), do: :ok

  defp save_reply(reply, message, reply_id) do
    save(message, reply_id, %{
      complete: true,
      tool_calls: reply.tool_calls,
      tool_results: reply.tool_results,
      text: final_text(reply)
    })
  end

  defp save(message, reply_id, attributes) do
    AshTemplate.Chat.Message
    |> Ash.Changeset.for_create(
      :upsert_response,
      Map.merge(
        %{id: reply_id, response_to_id: message.id, conversation_id: message.conversation_id},
        attributes
      ),
      actor: %AshAi{}
    )
    |> Ash.create!()
  end

  defp final_text(%{stream_error: nil, text: text} = reply) do
    if String.trim(text) == "" and (reply.tool_calls != [] or reply.tool_results != []),
      do: "Completed tool call.",
      else: text
  end

  defp final_text(%{stream_error: error, text: text}) do
    if String.trim(text) == "",
      do: error_text(error),
      else: text <> "\n\n" <> error_text(error)
  end

  defp name_conversation(message, context) do
    conversation =
      AshTemplate.Chat.get_conversation!(message.conversation_id,
        actor: context.actor,
        load: [:needs_title]
      )

    if conversation.needs_title,
      do: AshOban.run_trigger(conversation, :name_conversation, actor: context.actor)
  end

  defp tool_result(tool_call_id, {:ok, content, _raw}),
    do: %{tool_call_id: tool_call_id, content: content, is_error: false}

  defp tool_result(tool_call_id, {:error, content}),
    do: %{tool_call_id: tool_call_id, content: content, is_error: true}

  defp error_text(:max_iterations_reached),
    do: "I hit a response limit while generating this reply. Please try again."

  defp error_text(_reason),
    do: "I hit an error while generating this response. Please try again."
end

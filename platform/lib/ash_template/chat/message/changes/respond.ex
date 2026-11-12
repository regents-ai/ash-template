defmodule AshTemplate.Chat.Message.Changes.Respond do
  @moduledoc """
  Writes the assistant's reply to a person's message, then queues naming the
  conversation. Runs in the job the message's `:respond` trigger queues, with no
  transaction open, so the job holds a database connection only for its reads
  before the model answers and its write after. The model is the free stand-in
  (`AshTemplate.Chat.StandIn`).

  The reply is saved twice through `:upsert_response`: empty and unfinished when
  it starts, which every open page hears, and whole when it ends. Each piece in
  between is only broadcast, as `"piece"` with `%{id: reply_id, text: piece}` on
  the conversation's topic: a page that heard the reply start shows the pieces,
  and the whole reply replaces them. Every attempt at a message, and its failure
  line, writes the reply already started for it, so a message has one reply
  however many attempts run.
  """

  use Ash.Resource.Change
  require Ash.Query

  alias ReqLLM.Context

  # The newest messages the model reads, the person's new one included: one page
  # of the chat, and at the longest message (4,000 characters) about 50,000
  # tokens, well inside the context of the model the stand-in is replaced with.
  @history 50

  @empty_reply %{text: "", tool_calls: [], tool_results: [], stream_error: nil}

  @impl true
  def change(changeset, _opts, context),
    do: Ash.Changeset.before_transaction(changeset, &respond(&1, context))

  defp respond(changeset, context) do
    message = changeset.data

    prompt = [
      Context.system("""
      You are a helpful chat bot.
      Your job is to use the tools at your disposal to assist the user.
      """)
      | message |> history(context) |> Enum.map(&prompt_message/1)
    ]

    reply_id = start(message)

    prompt
    |> AshAi.ToolLoop.stream(
      otp_app: :ash_template,
      # Only the chat's own tools; the rooms tools are for agents (`AshTemplate.Rooms`).
      tools: [:chat_list_conversations, :chat_message_history],
      model: %{provider: :stand_in, id: "reply"},
      actor: context.actor,
      tenant: context.tenant,
      context: Map.new(Ash.Context.to_opts(context))
    )
    |> Enum.reduce(@empty_reply, &collect(&1, &2, message, reply_id))
    |> finish(message, reply_id)

    name_conversation(message, context)
    changeset
  end

  # Replies that never finished hold no text, so they are left out.
  defp history(message, context) do
    AshTemplate.Chat.Message
    |> Ash.Query.filter(conversation_id == ^message.conversation_id)
    |> Ash.Query.filter(id != ^message.id and complete)
    |> Ash.Query.select([:text, :source])
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@history - 1)
    |> Ash.read!(scope: context)
    |> Enum.reverse([%{source: :user, text: message.text}])
  end

  # Historical tool call replay can break provider request validation for prior call IDs.
  # Keep replay text-only; current turn tool usage is handled by AshAi.ToolLoop.
  defp prompt_message(%{source: :agent, text: text}), do: Context.assistant(text)
  defp prompt_message(%{source: :user, text: text}), do: Context.user(text)

  defp start(message) do
    reply_id = reply_id(message)
    save(message, reply_id, %{text: "", complete: false})
    reply_id
  end

  # The reply an earlier attempt started, or a new one. The assistant reads it,
  # as it writes it: the job's actor may be an agent unpaired since it sent the
  # message.
  defp reply_id(message) do
    case Ash.load!(message, :response, actor: %AshAi{}) do
      %{response: nil} -> Ash.UUIDv7.generate()
      %{response: reply} -> reply.id
    end
  end

  defp collect({:content, content}, reply, _message, _reply_id) when content in [nil, ""],
    do: reply

  defp collect({:content, content}, reply, message, reply_id) do
    AshTemplateWeb.Endpoint.broadcast("chat:messages:#{message.conversation_id}", "piece", %{
      id: reply_id,
      text: content
    })

    %{reply | text: reply.text <> content}
  end

  defp collect({:tool_call, tool_call}, reply, _message, _reply_id),
    do: %{reply | tool_calls: reply.tool_calls ++ [tool_call]}

  defp collect({:tool_result, %{id: id, result: result}}, reply, _message, _reply_id),
    do: %{reply | tool_results: reply.tool_results ++ [tool_result(id, result)]}

  defp collect({:error, reason}, reply, _message, _reply_id), do: %{reply | stream_error: reason}
  defp collect(_event, reply, _message, _reply_id), do: reply

  defp finish(reply, message, reply_id) do
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

  # A reply already started must end with something to read.
  defp final_text(%{stream_error: nil, text: text} = reply) do
    cond do
      String.trim(text) != "" -> text
      reply.tool_calls != [] or reply.tool_results != [] -> "Completed tool call."
      true -> error_text(:empty)
    end
  end

  defp final_text(%{stream_error: error, text: text}) do
    if String.trim(text) == "",
      do: error_text(error),
      else: text <> "\n\n" <> error_text(error)
  end

  @doc """
  Ends the reply to `message`, the one already started or a new one, with a line
  saying it failed, so every open page stops waiting for it. The message's
  `:fail_response` action calls it when the reply's job has failed for good.
  """
  def save_failed(message),
    do: save(message, reply_id(message), %{complete: true, text: error_text(:failed)})

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

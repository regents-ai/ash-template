defmodule AshTemplate.Chat.StandIn do
  @moduledoc """
  A free stand-in for a language model, so the chat page works without an API
  key or any paid call. It plugs into ReqLLM as a provider that answers on this
  server, a word at a time, the way a real model streams:

    * `%{provider: :stand_in, id: "reply"}` answers the person's latest message
      by quoting it back.
    * `%{provider: :stand_in, id: "title"}` names a conversation from its
      opening message.

  To use a real model, change the model in `Message.Changes.Respond` and
  `Conversation.Changes.GenerateName` (for example to `"openai:gpt-4o"`) and set
  that provider's API key in `config/runtime.exs`.
  """

  use ReqLLM.Provider, id: :stand_in, default_base_url: "http://localhost"

  alias ReqLLM.{Message, StreamChunk}

  @word_pause_ms 60
  @title_words 6

  @impl ReqLLM.Provider
  def stream_transport(_model, _opts), do: :in_process

  @impl ReqLLM.Provider
  def attach_in_process_stream(model, context, _opts) do
    words = model.id |> answer(user_messages(context)) |> String.split(" ")

    chunks =
      words
      |> Enum.with_index()
      |> Stream.map(fn {word, index} ->
        Process.sleep(@word_pause_ms)
        StreamChunk.text(if index == 0, do: word, else: " " <> word)
      end)
      |> Stream.concat([StreamChunk.meta(%{finish_reason: :stop})])

    {:ok, chunks}
  end

  defp answer("title", [opening | _]) do
    opening
    |> String.replace(~r/[*_`#>\[\]]/, "")
    |> String.split()
    |> Enum.take(@title_words)
    |> Enum.join(" ")
  end

  defp answer("reply", messages) do
    "I'm a stand-in for the assistant, so I don't read what you write, but this is " <>
      "how a reply arrives: a few words at a time, saved as they come and shown on " <>
      "every page that has this conversation open. You wrote: “#{List.last(messages)}”"
  end

  defp user_messages(context) do
    for %Message{role: :user} = message <- context.messages, do: text(message)
  end

  defp text(%Message{content: parts}),
    do: parts |> Enum.map_join(" ", &(&1.text || "")) |> String.trim()
end

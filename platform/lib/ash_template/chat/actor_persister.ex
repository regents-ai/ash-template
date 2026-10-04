defmodule AshTemplate.Chat.ActorPersister do
  @moduledoc """
  Carries the person who sent a chat message into the job that writes the
  assistant's reply, so the reply reads only that person's conversation.
  """

  use AshOban.ActorPersister

  alias AshTemplate.Actors.Human

  def store(%Human{human_account_id: id, name: name}),
    do: %{"type" => "human", "human_account_id" => id, "name" => name}

  def lookup(%{"type" => "human", "human_account_id" => id, "name" => name}),
    do: {:ok, %Human{human_account_id: id, name: name}}
end

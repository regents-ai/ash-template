defmodule AshTemplate.SharedReading.Heal do
  @moduledoc """
  Asks the producer of one kind of shared reading to read all its keys again
  (`AshTemplate.SharedReading.heal/1`). The site's schedule runs it each minute
  for every kind a producer rereads on notice, because a notice is sent at most
  once and can be lost. One attempt: the next minute's run replaces a failed one.
  One reread of a kind waits at a time, so a busy queue never piles up a minute's
  worth each minute; a reread left running on a stopped machine never holds up the
  next one.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:kind], period: :infinity, states: [:available, :scheduled, :retryable]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind}}),
    do: kind |> String.to_existing_atom() |> AshTemplate.SharedReading.heal()
end

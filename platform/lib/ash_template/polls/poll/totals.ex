defmodule AshTemplate.Polls.Poll.Totals do
  @moduledoc """
  A closed poll's result as anyone reads it: each choice's count of votes,
  `[%{choice, votes}]`, in the order the choices were listed, without who voted.
  Nil while the poll is open, so no one sees which way it leans before it closes.
  The counts come from the poll's own row (`tally`), kept by each vote.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:choices, :tally, :closes_at, :ended_at]

  @impl true
  def calculate(polls, _opts, _context) do
    now = DateTime.utc_now()
    Enum.map(polls, &if(AshTemplate.Polls.open?(&1, now), do: nil, else: totals(&1)))
  end

  defp totals(poll), do: Enum.map(poll.choices, &%{choice: &1, votes: Map.get(poll.tally, &1, 0)})
end

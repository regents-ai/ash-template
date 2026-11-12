defmodule AshTemplate.Polls.Poll.Starter do
  @moduledoc """
  Who started each poll, as `%{name, wallet, ens_name, squares, picture}`: the
  name they chose, else `nil` and they show by their wallet under its ENS name
  when it has one, and their picture (`AshTemplate.PublicIdentity.of_accounts/1`).
  Read by the site, since their account is private and only these leave it.
  """

  use Ash.Resource.Calculation

  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, _opts, _context), do: [:started_by_id]

  @impl true
  def calculate(polls, _opts, _context),
    do: polls |> Enum.map(& &1.started_by_id) |> PublicIdentity.of_accounts()
end

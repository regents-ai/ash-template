defmodule AshTemplate.Polls.Poll.Starter do
  @moduledoc """
  Who started each poll, as `%{name: name, squares: squares, picture: picture}`:
  their public name and picture (`AshTemplate.PublicIdentity`), read by the
  site, since their account is private and only the name and picture leave it.
  """

  use Ash.Resource.Calculation

  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, _opts, _context), do: [:started_by_id]

  @impl true
  def calculate(polls, _opts, _context),
    do: polls |> Enum.map(& &1.started_by_id) |> PublicIdentity.of_accounts()
end

defmodule AshTemplate.Polls.Poll.Starter do
  @moduledoc """
  Who started each poll, as `%{name: name, squares: squares, picture: picture}`:
  their public name and picture (`AshTemplate.PublicIdentity`), read by the
  site, since their account is private and only the name and picture leave it.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Actors.System
  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, _opts, _context), do: [:started_by_id]

  @impl true
  def calculate(polls, _opts, _context) do
    accounts = accounts(Enum.map(polls, & &1.started_by_id))

    Enum.map(polls, fn poll ->
      account = Map.get(accounts, poll.started_by_id, %{})

      %{
        name: PublicIdentity.label(account),
        squares: PublicIdentity.squares(account),
        picture: PublicIdentity.picture(account)
      }
    end)
  end

  defp accounts([]), do: %{}

  defp accounts(ids) do
    HumanAccount
    |> Ash.Query.filter(id in ^Enum.uniq(ids))
    |> Ash.Query.load([:display_name, :ens_name, :ens_avatar_url])
    |> Ash.read!(actor: %System{})
    |> Map.new(&{&1.id, &1})
  end
end

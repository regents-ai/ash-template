defmodule AshTemplate.Dms.Conversation.OtherPerson do
  @moduledoc """
  The other side of each conversation from the reader, as
  `%{name, wallet, ens_name, squares, picture}`: the name they chose, else `nil`
  and they show by their wallet under its ENS name when it has one, and their
  picture (`AshTemplate.PublicIdentity`). Read by the site, since their account
  is private and only these leave it.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Actors.System
  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, _opts, _context), do: [:person_a, :person_b]

  @impl true
  def calculate(conversations, _opts, %{actor: actor}) do
    me = Map.get(actor || %{}, :human_account_id)
    others = Enum.map(conversations, &if(&1.person_a == me, do: &1.person_b, else: &1.person_a))
    accounts = accounts(others)

    Enum.map(others, fn id ->
      account = Map.get(accounts, id, %{})

      account
      |> PublicIdentity.person()
      |> Map.merge(%{
        squares: PublicIdentity.squares(account),
        picture: PublicIdentity.picture(account)
      })
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

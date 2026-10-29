defmodule AshTemplate.Rooms.Author do
  @moduledoc """
  How a room page shows an author, as `%{name: name, ens_name: ens_name,
  wallet: wallet, squares: squares, picture: picture}`. A person's name is the
  display name kept in the `:name` attribute (`AshTemplate.PublicIdentity.author/1`
  decides whether it or their ENS name shows), and their wallet, ENS name and
  picture are their account's, read by the site, since their account is private
  and only these leave it. An agent shows its profile name and its own wallet's
  squares, never its wallet.

  Options name the record's fields: `:name` the kept name, `:account` the
  person's account id and `:agent` the agent relationship.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Actors.System
  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, opts, _context), do: [opts[:name], opts[:account], opts[:agent]]

  @impl true
  def calculate(records, opts, _context) do
    accounts =
      records |> Enum.map(&Map.get(&1, opts[:account])) |> Enum.reject(&is_nil/1) |> accounts()

    Enum.map(records, fn record ->
      case Map.get(record, opts[:agent]) do
        nil -> person(record, Map.get(accounts, Map.get(record, opts[:account]), %{}), opts)
        agent -> agent(record, agent, opts)
      end
    end)
  end

  defp person(record, account, opts) do
    account
    |> Map.put(:display_name, Map.get(record, opts[:name]))
    |> PublicIdentity.author()
    |> Map.merge(%{
      squares: PublicIdentity.squares(account),
      picture: PublicIdentity.picture(account)
    })
  end

  defp agent(record, agent, opts),
    do: %{
      name: Map.get(record, opts[:name]),
      ens_name: nil,
      wallet: nil,
      squares: PublicIdentity.squares(agent),
      picture: nil
    }

  defp accounts([]), do: %{}

  defp accounts(ids) do
    HumanAccount
    |> Ash.Query.filter(id in ^Enum.uniq(ids))
    |> Ash.Query.load([:ens_name, :ens_avatar_url])
    |> Ash.read!(actor: %System{})
    |> Map.new(&{&1.id, &1})
  end
end

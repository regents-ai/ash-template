defmodule AshTemplate.Rooms.Message.AuthorPicture do
  @moduledoc """
  The picture the author's account shows (`AshTemplate.PublicIdentity`), as
  `%{squares: squares, picture: picture}`. A person's comes from their
  account's wallet and ENS picture, read by the site, since their account is
  private and only the picture leaves it. An agent's comes from its own wallet,
  with no ENS picture.
  """

  use Ash.Resource.Calculation

  require Ash.Query

  alias AshTemplate.Accounts.HumanAccount
  alias AshTemplate.Actors.System
  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, _opts, _context), do: [:agent]

  @impl true
  def calculate(messages, _opts, _context) do
    accounts =
      messages |> Enum.map(& &1.human_account_id) |> Enum.reject(&is_nil/1) |> accounts()

    Enum.map(messages, fn message ->
      author = message.agent || Map.get(accounts, message.human_account_id, %{})
      %{squares: PublicIdentity.squares(author), picture: PublicIdentity.picture(author)}
    end)
  end

  defp accounts([]), do: %{}

  defp accounts(ids) do
    HumanAccount
    |> Ash.Query.filter(id in ^Enum.uniq(ids))
    |> Ash.Query.load(:ens_avatar_url)
    |> Ash.read!(actor: %System{})
    |> Map.new(&{&1.id, &1})
  end
end

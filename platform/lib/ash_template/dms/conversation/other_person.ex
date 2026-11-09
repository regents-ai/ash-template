defmodule AshTemplate.Dms.Conversation.OtherPerson do
  @moduledoc """
  The other side of each conversation from the reader, as
  `%{name: name, squares: squares, picture: picture}`: their public name and
  picture (`AshTemplate.PublicIdentity`), read by the site, since their account
  is private and only the name and picture leave it.
  """

  use Ash.Resource.Calculation

  alias AshTemplate.PublicIdentity

  @impl true
  def load(_query, _opts, _context), do: [:person_a, :person_b]

  @impl true
  def calculate(conversations, _opts, %{actor: actor}) do
    me = Map.get(actor || %{}, :human_account_id)

    conversations
    |> Enum.map(&if(&1.person_a == me, do: &1.person_b, else: &1.person_a))
    |> PublicIdentity.of_accounts()
  end
end

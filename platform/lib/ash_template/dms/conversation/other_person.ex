defmodule AshTemplate.Dms.Conversation.OtherPerson do
  @moduledoc """
  The other side of each conversation from the reader, as
  `%{name, wallet, ens_name, squares, picture}`: the name they chose, else `nil`
  and they show by their wallet under its ENS name when it has one, and their
  picture (`AshTemplate.PublicIdentity.of_accounts/1`). Read by the site, since
  their account is private and only these leave it.
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

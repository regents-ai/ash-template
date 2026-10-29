defmodule AshTemplate.PublicIdentityTest do
  use ExUnit.Case, async: true

  alias AshTemplate.PublicIdentity

  @wallet "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01"

  # Invariant: the wallet shows exactly when no name does, on the page and in the API.
  test "an author shows their display name, else their ENS name over their wallet, else their wallet" do
    account = %{wallet_address: @wallet, display_name: "Ada", ens_name: "ada.eth"}
    wallet = String.downcase(@wallet)

    assert PublicIdentity.author(account) == %{name: "Ada", ens_name: nil, wallet: nil}

    assert PublicIdentity.author(%{account | display_name: " "}) ==
             %{name: nil, ens_name: "ada.eth", wallet: wallet}

    assert PublicIdentity.author(%{account | display_name: nil, ens_name: nil}) ==
             %{name: nil, ens_name: nil, wallet: wallet}
  end
end

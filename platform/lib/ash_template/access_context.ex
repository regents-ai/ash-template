defmodule AshTemplate.AccessContext do
  @moduledoc "Who a public shell page is rendered for: nobody, or a signed-in account."

  alias __MODULE__.AccountControl
  alias AshTemplate.PublicIdentity

  @enforce_keys [:principal]
  defstruct @enforce_keys

  def anonymous, do: %__MODULE__{principal: :anonymous}

  def human(account), do: %__MODULE__{principal: {:human, account}}

  @doc "The only wallets that may act for the account, lowercase and each once; `nil` signed out."
  def linked_wallets(%__MODULE__{principal: {:human, account}}),
    do: account.wallet_addresses |> Enum.map(&String.downcase/1) |> Enum.uniq()

  def linked_wallets(%__MODULE__{principal: :anonymous}), do: nil

  def account_control(%__MODULE__{principal: :anonymous}),
    do: %AccountControl{kind: :sign_in, label: "Sign In"}

  def account_control(%__MODULE__{principal: {:human, account}}) do
    %AccountControl{
      kind: :signed_in,
      label: PublicIdentity.label(account),
      avatar_src: PublicIdentity.avatar_src(account)
    }
  end
end

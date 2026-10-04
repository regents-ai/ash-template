defmodule AshTemplate.Agents do
  @moduledoc "Agents that sign in with a wallet and act on the site as themselves."

  use Ash.Domain

  resources do
    resource AshTemplate.Agents.Agent do
      define :sign_in_agent, action: :sign_in, args: [:wallet_address]
    end
  end
end

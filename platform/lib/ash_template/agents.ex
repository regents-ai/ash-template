defmodule AshTemplate.Agents do
  @moduledoc """
  Agents that sign in with a wallet. An agent acts as itself, or, once paired
  with a person and backed by a person verified with World ID, as that person.
  """

  use Ash.Domain

  resources do
    resource AshTemplate.Agents.Agent do
      define :sign_in_agent, action: :sign_in, args: [:wallet_address]
      define :record_backing, action: :record_backing, args: [:human_id, :agent_count]
    end

    resource AshTemplate.Agents.Pairing do
      define :get_pairing, action: :by_wallet, args: [:wallet], not_found_error?: false
    end
  end
end

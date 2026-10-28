defmodule AshTemplate.Agents do
  @moduledoc """
  Agents that sign in with a wallet, and the operation keys they spend
  (`AshTemplate.Agents.Operation`). Signed in, an agent may post once in a room as
  itself; an active pairing permits supported account actions while retaining the
  agent's identity. World ID is optional. Each agent sets its own public profile.
  """

  use Ash.Domain

  resources do
    resource AshTemplate.Agents.Agent do
      define :sign_in_agent, action: :sign_in, args: [:wallet_address]
      define :record_backing, action: :record_backing, args: [:human_id, :agent_count]
      define :use_post_before_pairing, action: :use_post_before_pairing
      define :get_agent, action: :read, get_by: [:id]
      define :edit_agent_profile, action: :edit_profile
    end

    resource AshTemplate.Agents.Operation do
      define :get_operation,
        action: :read,
        get_by: [:principal, :capability, :operation_key],
        not_found_error?: false

      define :record_operation, action: :record
    end
  end
end

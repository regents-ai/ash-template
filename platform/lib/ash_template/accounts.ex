defmodule AshTemplate.Accounts do
  @moduledoc """
  Human accounts, their verified sessions, linked social identities and ENS
  names, and what a paired agent reads of its person's Credits and Points
  (`AshTemplate.Accounts.Holdings`). Those reads are also hosted agent tools
  (`tools`).
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource AshTemplate.Accounts.HumanAccount do
      define :points_account, action: :points_account, args: [:id]
      define :get_by_privy_did, action: :by_privy_did, args: [:privy_did], not_found_error?: false
      define :get_human_account, action: :read_self, args: [:id]

      define :register_verified,
        action: :register_verified,
        args: [:privy_user_id, :wallet_address, :wallet_addresses]

      define :refresh_verified,
        action: :refresh_verified,
        args: [:wallet_address, :wallet_addresses]
    end

    resource AshTemplate.Accounts.SessionAuthority

    resource AshTemplate.Accounts.EnsIdentity do
      define :request_ens_lookup,
        action: :request_lookup,
        args: [:human_account_id, :wallet_address]
    end

    resource AshTemplate.Accounts.LinkedIdentity do
      define :upsert_linked_identity, action: :upsert_verified

      define :list_my_linked_identities, action: :read_mine
      define :list_linked_identities_for_account, action: :for_account, args: [:human_account_id]

      define :get_linked_identity_by_subject,
        action: :by_provider_subject,
        args: [:provider, :subject],
        not_found_error?: false

      define :remove_linked_identity, action: :remove_verified
    end

    resource AshTemplate.Accounts.Holdings do
      define :account_balances, action: :account_balances

      define :account_credits_history,
        action: :account_credits_history,
        args: [:after]

      define :account_points, action: :account_points
    end
  end

  # The hosted agent tools: each runs the same action as its HTTP route, its
  # browser tool and its regents-cli command, and is named after them
  # (`AshTemplateWeb.Capabilities` checks both).
  tools do
    tool :account_balances, AshTemplate.Accounts.Holdings, :account_balances do
      description "Read your person's Credits and what you may spend of them on this site: your grant, its limits and what is left today. Changes nothing. Needs a pairing."
    end

    tool :account_credits_history, AshTemplate.Accounts.Holdings, :account_credits_history do
      description "Read what came into and went out of your person's Credits, newest first, a page at a time. Changes nothing. Needs a pairing."
    end

    tool :account_points, AshTemplate.Accounts.Holdings, :account_points do
      description "Read your person's Points: the total, today's, each daily allowance left and the latest entries, as the Points page shows them. Changes nothing. Needs a pairing."
    end
  end
end

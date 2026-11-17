defmodule AshTemplate.Agents.PairedAccount do
  @moduledoc """
  How the shared agent requests (`RegentAgents.HTTP`) name the person an agent is
  paired with: an agent's check-in (`GET /api/agents/v1/me`) names their account
  here, including its verified wallet fields, and the SIWA service's pairing read
  (`POST /api/agents/v1/pairing`) names them by their profile code. The check-in
  callback runs after the shared signed check-in; it is not a passive identity
  probe.
  """

  alias AshTemplate.Agents.ForPerson

  # Nil while the agent does not act for its person (`ForPerson.account/1`),
  # and when the account could not be read; the check-in then answers as for a
  # person not here, which asks for their sign-in.
  def account(privy_user_id) do
    case ForPerson.account(privy_user_id) do
      {:ok, account} ->
        %{
          display_name: account.display_name,
          ens_name: account.ens_name,
          wallet_address: account.wallet_address,
          wallet_addresses: account.wallet_addresses
        }

      {:error, _not_here_or_unread} ->
        nil
    end
  end

  @doc """
  The person's profile code: the ID of their shared Regent profile
  (`RegentIdentity.profile_id/2`), which a hello card names as its `person`. Nil
  until they have a profile, which their first sign-in with a wallet makes; the
  pairing read then answers `person_has_no_profile`. A profile that can't be read
  raises, so the SIWA service hears the site failed, never that the agent is not
  paired.
  """
  @spec person(String.t()) :: String.t() | nil
  def person(privy_user_id) do
    app_id = :ash_template |> Application.fetch_env!(:privy) |> Keyword.fetch!(:app_id)
    {:ok, profile_id} = RegentIdentity.profile_id(app_id, privy_user_id)
    profile_id
  end
end

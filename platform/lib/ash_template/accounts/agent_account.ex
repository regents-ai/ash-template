defmodule AshTemplate.Accounts.AgentAccount do
  @moduledoc """
  An account an agent owns: one it opened for itself, whose sign-in wallet is the
  agent's own signing wallet (Sean, 29 Oct 2026, 2. a). The agent's signed request
  then acts as the account's owner, as the person signed in on the site would
  (`AshTemplate.Actors.Human.owner/2`).

  The agent opens it with `open/1`. The site asks Privy for the user the wallet
  signs in to, makes one for the agent when there is none, then registers the
  account as a sign-in on the site does and records the opening
  (`AshTemplate.Accounts.AgentOwnedAccount`) in one transaction. Only a Privy user
  an agent opening made, here or on another Regent site, is taken
  (`RegentPrivy.Users`, `agent: true`); any other is a person's, even one who signs
  in with nothing but the same wallet.
  """

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.{AgentOwnedAccount, HumanAccount, VerifiedSession}
  alias AshTemplate.Actors.System
  alias AshTemplate.Agents.PairedAccount

  @actor %System{}

  @doc """
  The account `wallet` opened, while the wallet still signs in to it and its
  wallet evidence is current, or nil.
  """
  def owned(wallet) do
    wallet = String.downcase(wallet)

    with {:ok, opened} <- Accounts.get_agent_owned_account(wallet, actor: @actor) do
      case opened do
        %{human_account: %{wallet_address: ^wallet} = account} ->
          {:ok, if(VerifiedSession.current?(account), do: account)}

        _none_or_moved ->
          {:ok, nil}
      end
    end
  end

  @doc "How an agent's whoami names the account it owns (`config :regent_agents, owned_account:`)."
  def owned_account(wallet) do
    {:ok, account} = owned(wallet)
    account && PairedAccount.present(account)
  end

  @doc """
  Opens the account `wallet` owns, or answers the one it already owns. Errors
  are `:wallet_in_use` (the wallet signs in to a person's account), Privy's
  `:missing_privy_config`, `:privy_refused` and `:privy_unavailable`
  (`RegentPrivy.Users`), or the database's own.
  """
  def open(wallet) do
    wallet = String.downcase(wallet)

    with {:ok, nil} <- owned(wallet),
         {:ok, did} <- privy_user(wallet),
         {:ok, {:ok, account}} <-
           Ash.transact([HumanAccount, AgentOwnedAccount], fn -> register(did, wallet) end) do
      {:ok, account}
    end
  end

  defp register(did, wallet) do
    with {:ok, account} <- VerifiedSession.register(did, wallet, [wallet]),
         {:ok, _opened} <-
           Accounts.record_agent_owned_account(
             %{wallet_address: wallet, human_account_id: account.id},
             actor: @actor
           ) do
      {:ok, account}
    end
  end

  defp privy_user(wallet) do
    privy = Application.get_env(:ash_template, :privy, [])

    case RegentPrivy.Users.by_wallet(wallet, privy) do
      {:ok, %{privy_user_id: did, agent: true}} -> {:ok, did}
      {:ok, %{agent: false}} -> {:error, :wallet_in_use}
      {:error, :not_found} -> made(RegentPrivy.Users.create_with_wallet(wallet, privy))
      {:error, error} -> {:error, error}
    end
  end

  defp made({:ok, %{privy_user_id: did}}), do: {:ok, did}
  defp made({:error, error}), do: {:error, error}
end

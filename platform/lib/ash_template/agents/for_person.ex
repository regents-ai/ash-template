defmodule AshTemplate.Agents.ForPerson do
  @moduledoc """
  The one rule for whether a paired agent acts for its person right now: its
  wallet's pairing is active, and the person's latest sign-in here named a
  wallet (`AshTemplate.Accounts.VerifiedSession.current?/1`). Before their first
  sign-in here, and after one with no wallet linked, the person is not here;
  their next sign-in with a wallet lets the agent act for them again.

  Every place an agent acts for its person asks here: a signed request as it
  arrives and again just before its answer leaves
  (`AshTemplateWeb.Plugs.AgentWallet`), an open feed whenever its pairing or its
  person's sign-in changes (`AshTemplateWeb.FeedController`), a job as it runs
  (`AshTemplate.Actors.Persister`), and a check-in
  (`AshTemplate.Agents.PairedAccount`).
  """

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.VerifiedSession
  alias AshTemplate.Actors.{Agent, System}

  @typedoc "Why the agent does not act for a person now."
  @type refusal :: :not_paired | :person_not_here

  @doc "The wallet's active pairing and the person's account, while the agent acts for them."
  @spec resolve(String.t()) :: {:ok, map(), Ash.Resource.record()} | {:error, refusal() | term()}
  def resolve(wallet) do
    with {:ok, pairing} <- RegentAgents.Authority.resolve(AshTemplate.Repo, wallet),
         {:ok, account} <- account(pairing.privy_user_id),
         do: {:ok, pairing, account}
  end

  @doc """
  Whether `agent`, read earlier as acting for its person, still acts for that
  same person under that same pairing.
  """
  @spec still(Agent.t()) :: :ok | {:error, refusal() | term()}
  def still(%Agent{
        pairing: :active,
        wallet_address: wallet,
        pairing_id: id,
        privy_user_id: person
      }) do
    case RegentAgents.Authority.resolve(AshTemplate.Repo, wallet) do
      {:ok, %{id: ^id, privy_user_id: ^person}} ->
        with {:ok, _account} <- account(person), do: :ok

      {:ok, _other_pairing} ->
        {:error, :not_paired}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The person's account, while their latest sign-in here named a wallet."
  @spec account(String.t()) :: {:ok, Ash.Resource.record()} | {:error, :person_not_here | term()}
  def account(privy_user_id) do
    with {:ok, account} <- Accounts.get_by_privy_did(privy_user_id, actor: %System{}) do
      if VerifiedSession.current?(account),
        do: {:ok, account},
        else: {:error, :person_not_here}
    end
  end
end

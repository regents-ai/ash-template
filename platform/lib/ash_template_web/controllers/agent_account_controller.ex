defmodule AshTemplateWeb.AgentAccountController do
  @moduledoc """
  An agent opens its own account (`AshTemplate.Accounts.AgentAccount`): the wallet
  that signs its requests becomes the account's sign-in wallet, and its signed
  requests then act as the account's owner. The body is an empty JSON object.
  Opening again answers the same account. One address opens at most `:account_open_address` accounts a day.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.{Accounts, Limits}
  alias AshTemplate.Accounts.AgentAccount
  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Agents.PairedAccount
  alias AshTemplateWeb.{ClientAddress, UnexpectedFailure}

  @errors %{
    "invalid_account_request" =>
      {422, "Opening an account takes no input.", "Send an empty JSON object."},
    "agent_paired" =>
      {409, "This agent is paired with a person and acts for their account.",
       "Ask your person to remove the pairing on their Account page, then open your own account."},
    "wallet_in_use" =>
      {409, "This wallet already signs in to a person's account.",
       "Sign your requests with a wallet of the agent's own to open its account."},
    "account_not_opened" =>
      {409, "The account could not be opened.",
       "Read your status with GET /api/agents/v1/whoami, then send the request again."},
    "account_openings_limited" =>
      {429, "This network has opened its accounts for today.",
       "Wait the number of seconds in Retry-After, then send the request again."},
    "accounts_unavailable" =>
      {503, "Accounts can't be opened right now.", "Try again in a moment."}
  }

  def open(%{body_params: body} = conn, _params) when body != %{},
    do: refuse(conn, "invalid_account_request")

  def open(%{assigns: %{actor: %Human{} = owner}} = conn, _params) do
    case Accounts.get_human_account(owner.human_account_id, actor: owner) do
      {:ok, account} -> answer(conn, account)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("accounts_unavailable")
    end
  end

  def open(%{assigns: %{actor: %Agent{pairing: :none} = agent}} = conn, _params) do
    with {:ok, conn} <- spend(conn),
         {:ok, account} <- AgentAccount.open(agent.wallet_address) do
      answer(conn, account)
    else
      {:limited, conn} -> refuse(conn, "account_openings_limited")
      {:error, :wallet_in_use} -> refuse(conn, "wallet_in_use")
      {:error, :privy_refused} -> refuse(conn, "account_not_opened")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("accounts_unavailable")
    end
  end

  def open(conn, _params), do: refuse(conn, "agent_paired")

  defp spend(conn) do
    case Limits.spend_until(:account_open_address, ClientAddress.client_key(conn)) do
      :ok -> {:ok, conn}
      {:limited, seconds} -> {:limited, put_resp_header(conn, "retry-after", "#{seconds}")}
    end
  end

  defp answer(conn, account), do: json(conn, %{account: PairedAccount.present(account)})

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end

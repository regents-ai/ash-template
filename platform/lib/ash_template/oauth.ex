defmodule AshTemplate.OAuth do
  @moduledoc """
  Consent for connected apps, such as Claude's connector, through the person's
  verified account. The one permission lets the app keep an identity, pair it
  with this account and check in through the MCP address at `/mcp`; nothing else.
  """
  @behaviour RegentOAuth

  def config, do: Application.fetch_env!(:ash_template, __MODULE__)
  def repo, do: AshTemplate.Repo

  @doc """
  Whether the Claude connector is switched on (`ASH_TEMPLATE_CLAUDE_CONNECTOR_ENABLED`,
  read once at boot): its sign-in, its MCP address, Claude in the pairing box and
  the Claude guide all follow this one setting.
  """
  def enabled?, do: Keyword.fetch!(config(), :enabled?)

  def current_subject(conn) do
    case conn.assigns[:current_human_account] do
      %{privy_user_id: subject} = account ->
        if AshTemplate.Accounts.VerifiedSession.current?(account), do: subject

      _ ->
        nil
    end
  end

  def active_subject?(subject) do
    case AshTemplate.Accounts.get_by_privy_did(subject, actor: %AshTemplate.Actors.System{}) do
      {:ok, account} -> AshTemplate.Accounts.VerifiedSession.current?(account)
      {:error, error} -> raise error
    end
  end
end

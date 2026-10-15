defmodule AshTemplate.OAuth do
  @moduledoc "Opt-in MCP consent through the site's existing verified Privy account."
  @behaviour RegentOAuth

  def config, do: Application.fetch_env!(:ash_template, __MODULE__)
  def repo, do: AshTemplate.Repo

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

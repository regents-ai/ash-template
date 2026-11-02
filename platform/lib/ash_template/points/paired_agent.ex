defmodule AshTemplate.Points.PairedAgent do
  @moduledoc """
  Regent Points' check of a pairing: it reads the pairing's history row, kept
  after an unpair, and answers with what Points records for the person who
  made the pairing code.
  """

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.System

  def verify(%{"source_event_key" => id}) do
    case Ecto.Adapters.SQL.query(
           AshTemplate.Repo,
           "SELECT privy_user_id, paired_at FROM regent_agents.pairing_history WHERE id = $1",
           [Ecto.UUID.dump!(id)]
         ) do
      {:ok, %{rows: [[privy_user_id, paired_at]]}} -> with_account(id, privy_user_id, paired_at)
      {:ok, _} -> {:error, :pairing_not_found}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp with_account(id, privy_user_id, paired_at) do
    case Accounts.get_by_privy_did(privy_user_id, actor: %System{}) do
      {:ok, %{} = account} -> {:ok, facts(id, account, paired_at)}
      {:ok, nil} -> {:error, :pairing_account_not_found}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp facts(id, account, paired_at) do
    # The column is a UTC time without its zone.
    paired_at = DateTime.from_naive!(paired_at, "Etc/UTC")

    %{
      source_app: AshTemplate.site(),
      source_kind: "pairing",
      source_event_key: id,
      account_id: account.id,
      actor_kind: "agent",
      # The pairing's id, so the Points page names the agent the person paired.
      actor_id: id,
      source_action_at: paired_at,
      qualified_at: paired_at,
      evidence_ref: "pairing:" <> id,
      evidence: %{"attribution_link_id" => id}
    }
  end
end

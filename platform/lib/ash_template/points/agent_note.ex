defmodule AshTemplate.Points.AgentNote do
  @moduledoc """
  Regent Points' check of a note an agent wrote: it reads the saved note and
  answers with what Points records. Attribution uses the creation-time episode,
  even after an edit, revocation or re-pairing. Old notes without that evidence
  cannot be attributed by guessing from the current wallet owner.
  """

  alias AshTemplate.Notes

  def verify(%{"source_event_key" => id}) do
    # No person is asking: Points' server check reads the committed note it was given.
    case Notes.get_my_note(id, load: [:human_account], authorize?: false) do
      {:ok, %{created_by_pairing_id: id} = note} when is_binary(id) -> with_pairing(note)
      {:ok, %{}} -> {:error, :note_not_by_agent}
      {:ok, nil} -> {:error, :note_not_found}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp with_pairing(note) do
    privy_user_id = note.human_account.privy_user_id

    case RegentAgents.pairing_history(note.created_by_pairing_id) do
      {:ok, %{privy_user_id: ^privy_user_id} = pairing} -> {:ok, facts(note, pairing)}
      {:ok, _} -> {:error, :agent_not_paired_with_writer}
    end
  end

  defp facts(note, pairing) do
    %{
      source_app: AshTemplate.site(),
      source_kind: "note",
      source_event_key: note.id,
      account_id: note.human_account_id,
      actor_kind: "agent",
      # The agent's wallet, so the Points page names the agent the person paired.
      actor_id: pairing.wallet,
      source_action_at: note.inserted_at,
      qualified_at: note.inserted_at,
      evidence_ref: "note:" <> note.id,
      evidence: %{"attribution_link_id" => pairing.id}
    }
  end
end

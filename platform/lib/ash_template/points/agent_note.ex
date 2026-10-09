defmodule AshTemplate.Points.AgentNote do
  @moduledoc """
  Regent Points' check of a note an agent wrote: it reads the saved note and
  answers with what Points records. Only a note whose latest save was by an agent
  still paired with the note's writer counts, for that writer, marked as the agent's.
  """

  alias AshTemplate.Actors.System
  alias AshTemplate.{Agents, Notes}

  def verify(%{"source_event_key" => id}) do
    # No person is asking: Points' server check reads the committed note it was given.
    case Notes.get_my_note(id, load: [:changed_by_agent, :human_account], authorize?: false) do
      {:ok, %{changed_by_agent: %{} = agent} = note} -> with_pairing(note, agent)
      {:ok, %{}} -> {:error, :note_not_by_agent}
      {:ok, nil} -> {:error, :note_not_found}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp with_pairing(note, agent) do
    writer = note.human_account.privy_user_id

    case Agents.get_pairing(agent.wallet_address, actor: %System{}) do
      {:ok, %{privy_user_id: ^writer} = pairing} -> {:ok, facts(note, pairing)}
      {:ok, _} -> {:error, :agent_not_paired_with_writer}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp facts(note, pairing) do
    %{
      source_app: "template",
      source_kind: "note",
      source_event_key: note.id,
      account_id: note.human_account_id,
      actor_kind: "agent",
      # The pairing's id, so the Points page names the agent the person paired.
      actor_id: pairing.id,
      source_action_at: note.inserted_at,
      qualified_at: note.inserted_at,
      evidence_ref: "note:" <> note.id,
      evidence: %{"attribution_link_id" => pairing.id}
    }
  end
end

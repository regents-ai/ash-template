defmodule AshTemplateWeb.NotesJSON do
  @moduledoc """
  A note as the notes API and the browser tools return it, with its latest label
  and the paired agent that made its latest save.
  """

  alias AshTemplate.Notes.{Decision, Note}

  @doc """
  The note's fields, its `label`, or `label: nil` when none was asked for, and
  `changed_by_agent`, or nil when its writer made the latest save.
  """
  @spec note(Note.t()) :: map()
  def note(%Note{} = note) do
    note
    |> Map.take([:id, :title, :body, :inserted_at, :updated_at])
    |> Map.put(:label, label(note.label_decision))
    |> Map.put(:changed_by_agent, agent(note.changed_by_agent))
  end

  defp agent(nil), do: nil
  defp agent(agent), do: %{wallet_address: agent.wallet_address}

  defp label(nil), do: nil

  defp label(%Decision{} = decision) do
    %{
      state: decision.state,
      choice: decision.choice,
      confidence: decision.confidence,
      rating: decision.report
    }
  end
end

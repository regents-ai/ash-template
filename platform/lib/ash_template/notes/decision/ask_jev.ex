defmodule AshTemplate.Notes.Decision.AskJev do
  @moduledoc """
  Asks Jev which label fits the decision's note, before the decision is
  written and outside any transaction.

  An answer is recorded with its model, tokens and cost. An answer Jev was
  billed for but that used no offered label is recorded as a failure with its
  cost, since asking again would ask the same thing. A request that did not
  get through fails the action, so the job retries with backoff.
  """

  use Ash.Resource.Change

  alias Ash.Error.Unknown.UnknownError
  alias AshTemplate.Notes.Labels
  alias RegentJev.Error

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      pairing_id = changeset.data.pairing_id

      if pairing_id && not RegentAgents.Authority.active_episode?(AshTemplate.Repo, pairing_id) do
        Ash.Changeset.force_change_attributes(changeset, %{
          state: :failed,
          failure: "Agent pairing revoked"
        })
      else
        ask(changeset)
      end
    end)
  end

  defp ask(changeset) do
    # Runs in the background job with no person behind it; the decision names
    # its own note, so reading that note is not a choice made by anyone.
    %{note: note} = Ash.load!(changeset.data, :note, authorize?: false)

    case RegentJev.decide(%{title: note.title, body: note.body}, Labels.questions(),
           model: Labels.model()
         ) do
      {:ok, %{answers: %{"label" => answer}} = decision} ->
        Ash.Changeset.force_change_attributes(changeset, %{
          state: :answered,
          choice: answer.choice,
          confidence: answer.confidence,
          model: decision.model,
          input_tokens: decision.usage.input_tokens,
          output_tokens: decision.usage.output_tokens,
          cost_usd: decision.cost_usd
        })

      {:error, %Error{usage: %{} = usage} = error} ->
        Ash.Changeset.force_change_attributes(changeset, %{
          state: :failed,
          failure: Exception.message(error),
          input_tokens: usage.input_tokens,
          output_tokens: usage.output_tokens,
          cost_usd: error.cost_usd
        })

      # A server fault, so a job that runs out of attempts reaches the error page.
      {:error, error} ->
        Ash.Changeset.add_error(
          changeset,
          UnknownError.exception(error: "Jev could not be asked: #{Exception.message(error)}")
        )
    end
  end
end

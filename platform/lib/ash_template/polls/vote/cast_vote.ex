defmodule AshTemplate.Polls.Vote.CastVote do
  @moduledoc """
  Records the actor's person's vote, or hands back the vote they already have.

  A first vote names one of the poll's choices and is counted on the poll's row
  in the same transaction (`AshTemplate.Polls.Poll` `:count_vote`). That count
  checks the poll is still open, so a poll closing or being ended at that moment
  either takes this vote or turns it away, never both. A person who already
  voted is answered with that vote whatever has happened to the poll since, so a
  voter that never heard the answer can ask again; a different choice is refused.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Actors.System
  alias AshTemplate.Polls.Poll

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    changeset
    |> Ash.Changeset.before_action(&place(&1, Map.get(actor || %{}, :human_account_id)))
    |> Ash.Changeset.force_change_attribute(
      :via_agent_id,
      Map.get(actor || %{}, :acting_agent_id)
    )
    |> Ash.Changeset.after_action(&count/2)
  end

  defp place(changeset, voter) do
    poll_id = Ash.Changeset.get_argument(changeset, :poll_id)
    choice = Ash.Changeset.get_attribute(changeset, :choice)

    # Anyone may read a poll; the vote itself was authorized.
    poll =
      Poll
      |> Ash.Query.filter(id == ^poll_id)
      |> Ash.read_one!(authorize?: false)

    cond do
      is_nil(poll) ->
        Ash.Changeset.add_error(changeset, field: :poll_id, message: "That poll isn’t here.")

      choice not in poll.choices ->
        Ash.Changeset.add_error(changeset,
          field: :choice,
          message: "Choose one of the poll’s choices."
        )

      true ->
        changeset
        |> Ash.Changeset.force_change_attributes(poll_id: poll.id, voter_id: voter)
        |> Ash.Changeset.set_context(%{poll: poll})
    end
  end

  # A vote saved now is counted; one already there is answered as it stands.
  defp count(changeset, vote) do
    cond do
      Ash.Resource.get_metadata(vote, :upsert_skipped) != true ->
        changeset.context.poll
        |> Ash.Changeset.for_update(:count_vote, %{choice: vote.choice}, actor: %System{})
        |> Ash.update()
        |> case do
          {:ok, _poll} -> {:ok, vote}
          error -> error
        end

      vote.choice == Ash.Changeset.get_attribute(changeset, :choice) ->
        {:ok, vote}

      true ->
        {:error,
         Ash.Error.Changes.InvalidAttribute.exception(
           field: :choice,
           message: "You already voted for “#{vote.choice}”. A vote can’t be changed."
         )}
    end
  end
end

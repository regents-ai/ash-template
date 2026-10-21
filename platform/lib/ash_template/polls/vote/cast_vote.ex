defmodule AshTemplate.Polls.Vote.CastVote do
  @moduledoc """
  Records the actor's person's vote, or hands back the vote they already have.

  A first vote needs the poll still open and one of its choices. The poll is
  read under a shared lock, so a poll being ended at that moment either takes
  this vote or turns it away, never both. A person who already voted is
  answered with that vote whatever has happened to the poll since, so a voter
  that never heard the answer can ask again; a different choice is refused.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias AshTemplate.Polls
  alias AshTemplate.Polls.{Poll, Vote}

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    changeset
    |> Ash.Changeset.before_action(&place(&1, Map.get(actor || %{}, :human_account_id)))
    |> Ash.Changeset.force_change_attribute(
      :via_agent_id,
      Map.get(actor || %{}, :acting_agent_id)
    )
    |> Ash.Changeset.after_action(&same_choice/2)
  end

  defp place(changeset, voter) do
    poll_id = Ash.Changeset.get_argument(changeset, :poll_id)
    choice = Ash.Changeset.get_attribute(changeset, :choice)

    # Anyone may read a poll; the vote itself was authorized.
    poll =
      Poll
      |> Ash.Query.filter(id == ^poll_id)
      |> Ash.Query.lock("FOR SHARE")
      |> Ash.read_one!(authorize?: false)

    cond do
      is_nil(poll) ->
        Ash.Changeset.add_error(changeset, field: :poll_id, message: "That poll isn’t here.")

      voted?(poll, voter) ->
        place_on(changeset, poll, voter)

      not Polls.open?(poll) ->
        Ash.Changeset.add_error(changeset, field: :poll_id, message: "This poll has closed.")

      choice not in poll.choices ->
        Ash.Changeset.add_error(changeset,
          field: :choice,
          message: "Choose one of the poll’s choices."
        )

      true ->
        place_on(changeset, poll, voter)
    end
  end

  defp place_on(changeset, poll, voter),
    do: Ash.Changeset.force_change_attributes(changeset, poll_id: poll.id, voter_id: voter)

  # Whether the person already voted decides this vote's answer; the vote
  # itself was authorized.
  defp voted?(poll, voter),
    do:
      Vote
      |> Ash.Query.filter(poll_id == ^poll.id and voter_id == ^voter)
      |> Ash.exists?(authorize?: false)

  defp same_choice(changeset, vote) do
    cond do
      Ash.Resource.get_metadata(vote, :upsert_skipped) != true ->
        {:ok, vote}

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

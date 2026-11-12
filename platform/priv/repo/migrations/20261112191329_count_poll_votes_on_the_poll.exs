defmodule AshTemplate.Repo.Migrations.CountPollVotesOnThePoll do
  @moduledoc """
  Each poll keeps its own count of votes (`AshTemplate.Polls.Poll`): how many have
  voted (`votes_cast`) and each choice's votes (`tally`), which every vote now adds
  to as it is saved. Two new columns with a default, so no row is rewritten to add
  them; then each poll that already has votes is given the counts of the votes it
  has. A poll with none keeps 0 and an empty tally. Votes are untouched.

  Generated with `mix ash.codegen count_poll_votes_on_the_poll`; the fill is by hand,
  since a fill has no Ash form.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:polls) do
      add(:votes_cast, :bigint, null: false, default: 0)
      add(:tally, :map, null: false, default: %{})
    end

    execute("""
    UPDATE #{prefix()}.polls AS p
    SET votes_cast = c.votes_cast, tally = c.tally
    FROM (
      SELECT poll_id, sum(votes)::bigint AS votes_cast, jsonb_object_agg(choice, votes) AS tally
      FROM (
        SELECT poll_id, choice, count(*) AS votes
        FROM #{prefix()}.poll_votes
        GROUP BY poll_id, choice
      ) AS v
      GROUP BY poll_id
    ) AS c
    WHERE p.id = c.poll_id
    """)
  end

  def down do
    alter table(:polls) do
      remove(:tally)
      remove(:votes_cast)
    end
  end
end

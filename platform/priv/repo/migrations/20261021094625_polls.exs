defmodule AshTemplate.Repo.Migrations.Polls do
  @moduledoc """
  Polls and their votes (`AshTemplate.Polls`): the polls table first, since
  each vote names its poll.
  """

  use Ecto.Migration

  def up do
    create table(:polls, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:question, :text, null: false)
      add(:choices, {:array, :text}, null: false)
      add(:closes_at, :utc_datetime_usec, null: false)
      add(:ended_at, :utc_datetime_usec)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :started_by_id,
        references(:platform_human_users,
          column: :id,
          name: "polls_started_by_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ),
        null: false
      )

      add(
        :via_agent_id,
        references(:agents,
          column: :id,
          name: "polls_via_agent_id_fkey",
          type: :uuid,
          prefix: "ash_template_app"
        )
      )
    end

    create constraint(:polls, :polls_choices_count,
             check: """
               cardinality(choices) BETWEEN 2 AND 10
             """
           )

    create index(:polls, [:inserted_at])

    create table(:poll_votes, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:choice, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :poll_id,
        references(:polls,
          column: :id,
          name: "poll_votes_poll_id_fkey",
          type: :uuid,
          prefix: "ash_template_app",
          on_delete: :delete_all
        ),
        null: false
      )

      add(
        :voter_id,
        references(:platform_human_users,
          column: :id,
          name: "poll_votes_voter_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ),
        null: false
      )

      add(
        :via_agent_id,
        references(:agents,
          column: :id,
          name: "poll_votes_via_agent_id_fkey",
          type: :uuid,
          prefix: "ash_template_app"
        )
      )
    end

    create unique_index(:poll_votes, [:poll_id, :voter_id], name: "poll_votes_unique_vote_index")
  end

  def down do
    drop(table(:poll_votes))
    drop(table(:polls))
  end
end

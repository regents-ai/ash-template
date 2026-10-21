defmodule AshTemplate.Repo.Migrations.DirectMessages do
  @moduledoc """
  Direct messages between two people: one conversation for each pair, the
  lower account id first, and its messages.
  """

  use Ecto.Migration

  def up do
    create table(:dm_conversations, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:blocked_by_a, :boolean, null: false, default: false)
      add(:blocked_by_b, :boolean, null: false, default: false)
      add(:last_message_at, :utc_datetime_usec)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :person_a,
        references(:platform_human_users,
          column: :id,
          name: "dm_conversations_person_a_fkey",
          type: :bigint,
          prefix: "regent_names"
        ), null: false)

      add(
        :person_b,
        references(:platform_human_users,
          column: :id,
          name: "dm_conversations_person_b_fkey",
          type: :bigint,
          prefix: "regent_names"
        ), null: false)

      add(
        :opened_by_id,
        references(:platform_human_users,
          column: :id,
          name: "dm_conversations_opened_by_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ), null: false)
    end

    create unique_index(:dm_conversations, [:person_a, :person_b],
             name: "dm_conversations_unique_pair_index"
           )

    create constraint(:dm_conversations, :dm_conversations_person_order,
             check: """
               person_a < person_b
             """
           )

    create index(:dm_conversations, [:person_b])

    create table(:dm_messages, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:body, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :conversation_id,
        references(:dm_conversations,
          column: :id,
          name: "dm_messages_conversation_id_fkey",
          type: :uuid,
          prefix: "ash_template_app",
          on_delete: :delete_all
        ), null: false)

      add(
        :from_id,
        references(:platform_human_users,
          column: :id,
          name: "dm_messages_from_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ), null: false)

      add(
        :to_id,
        references(:platform_human_users,
          column: :id,
          name: "dm_messages_to_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        ), null: false)

      add(
        :via_agent_id,
        references(:agents,
          column: :id,
          name: "dm_messages_via_agent_id_fkey",
          type: :uuid,
          prefix: "ash_template_app"
        )
      )
    end

    create index(:dm_messages, [:conversation_id, :inserted_at])
  end

  def down do
    drop(table(:dm_messages))
    drop(table(:dm_conversations))
  end
end

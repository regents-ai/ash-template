defmodule AshTemplate.Repo.Migrations.RoomsPeopleStart do
  @moduledoc """
  Rooms become rows. The site's own rooms, General and Help, are written here,
  General first, and every message's room must name one.
  """

  use Ecto.Migration

  def up do
    create table(:rooms, primary_key: false) do
      add(:slug, :text, null: false, primary_key: true)
      add(:name, :text, null: false)
      add(:topic, :text, null: false)

      add(:inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :created_by_id,
        references(:platform_human_users,
          column: :id,
          name: "rooms_created_by_id_fkey",
          type: :bigint,
          prefix: "regent_names"
        )
      )
    end

    execute("""
    INSERT INTO #{prefix()}.rooms (slug, name, topic, inserted_at) VALUES
      ('general', 'General', 'Say hello and talk about anything.',
       now() AT TIME ZONE 'utc'),
      ('help', 'Help', 'Ask how something works and help others find out.',
       (now() AT TIME ZONE 'utc') + interval '1 millisecond')
    """)

    alter table(:room_messages) do
      modify(
        :room,
        references(:rooms,
          column: :slug,
          name: "room_messages_room_fkey",
          type: :text,
          prefix: "ash_template_app"
        )
      )
    end
  end

  def down do
    drop(constraint(:room_messages, "room_messages_room_fkey"))

    alter table(:room_messages) do
      modify(:room, :text)
    end

    drop(constraint(:rooms, "rooms_created_by_id_fkey"))

    drop(table(:rooms))
  end
end

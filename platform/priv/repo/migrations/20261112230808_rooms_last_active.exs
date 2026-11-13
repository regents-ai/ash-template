defmodule AshTemplate.Repo.Migrations.RoomsLastActive do
  @moduledoc """
  Each room keeps when it was last active (`AshTemplate.Rooms.Room`
  `last_active_at`), which orders the list of rooms and which every post now
  moves. A new column with a default, so adding it rewrites no row; then, in
  the same transaction, each room is given the later of when it was started and
  when its newest saved message was posted: one update of each room's own row,
  reading only that room's newest message through the messages' room-and-time
  index. Messages are untouched.

  Generated with `mix ash.codegen rooms_last_active`; the fill is by hand, since
  a fill has no Ash form. Its index is built concurrently in the next migration.
  """

  use Ecto.Migration

  def up do
    execute("SET LOCAL lock_timeout = '5s'")

    alter table(:rooms) do
      add(:last_active_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )
    end

    flush()

    execute(fill(AshTemplate.Repo.default_prefix()))
  end

  def down do
    alter table(:rooms) do
      remove(:last_active_at)
    end
  end

  @doc "The statement `up/0` fills each room's time with, in the schema `prefix`."
  def fill(prefix) do
    """
    UPDATE #{prefix}.rooms AS r
    SET last_active_at = greatest(r.inserted_at, (
      SELECT max(m.inserted_at) FROM #{prefix}.room_messages AS m WHERE m.room = r.slug
    ))
    """
  end
end

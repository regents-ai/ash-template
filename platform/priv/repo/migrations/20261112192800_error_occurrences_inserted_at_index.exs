defmodule AshTemplate.Repo.Migrations.ErrorOccurrencesInsertedAtIndex do
  @moduledoc """
  The daily error prune (`AshTemplate.ErrorPruner`) finds occurrences older than
  a week by when they were saved; ErrorTracker indexes them only by their error.
  ErrorTracker's tables have no Ash resource, so `mix ash.codegen` cannot declare
  this index, and it is written here in the shape the generator gives a
  concurrent one (skills/ash-data/references/migrations-and-concurrency.md).
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create index(:error_tracker_occurrences, [:inserted_at],
             prefix: AshTemplate.Repo.default_prefix(),
             concurrently: true
           )
  end

  def down do
    drop_if_exists(
      index(:error_tracker_occurrences, [:inserted_at], prefix: AshTemplate.Repo.default_prefix())
    )
  end
end

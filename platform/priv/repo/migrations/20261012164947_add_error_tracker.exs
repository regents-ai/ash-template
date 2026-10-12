defmodule AshTemplate.Repo.Migrations.AddErrorTracker do
  use Ecto.Migration

  # ErrorTracker's own tables, in the schema the site's own tables use.
  def up, do: ErrorTracker.Migration.up(prefix: "ash_template_app", create_schema: false)
  def down, do: ErrorTracker.Migration.down(prefix: "ash_template_app", version: 1)
end

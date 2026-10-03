defmodule AshTemplate.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's job table, in the schema the site's own tables use.
  def up, do: Oban.Migrations.up(prefix: "ash_template_app")
  def down, do: Oban.Migrations.down(prefix: "ash_template_app")
end

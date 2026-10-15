defmodule AshTemplate.Repo.Migrations.AddOAuthProvider do
  use Ecto.Migration

  def up do
    RegentOAuth.Migration.up(
      issuer: "https://template.regents.sh",
      resource: "https://template.regents.sh"
    )
  end
end

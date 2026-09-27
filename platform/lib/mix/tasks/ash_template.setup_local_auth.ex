defmodule Mix.Tasks.AshTemplate.SetupLocalAuth do
  use Mix.Task

  @shortdoc "Prepares the guarded local Ash Template database"

  @impl true
  def run(_args) do
    unless Mix.env() == :dev, do: Mix.raise("local auth setup is dev only")
    Mix.Task.run("app.start")
    AshTemplate.LocalDatabaseFixture.ensure_human_accounts!()
    Mix.shell().info("Local Ash Template database is ready.")
  end
end

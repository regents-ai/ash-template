defmodule AshTemplate.LocalDatabaseFixture do
  @moduledoc false

  def ensure_human_accounts! do
    repo = AshTemplate.Repo.config()

    unless to_string(repo[:hostname]) in ["127.0.0.1", "::1"] and
             String.ends_with?(to_string(repo[:database]), "_dev") do
      raise "local human-account fixture refused unsafe database target"
    end

    create_shared_tables!()
    AshTemplate.Repo.migrate!(Application.app_dir(:ash_template, "priv/repo/migrations"))
    # Regents migrates the shared Credits ledger and profiles in production;
    # locally each site does.
    RegentCredits.Migrator.up(AshTemplate.Repo)
    RegentIdentity.Migrator.up(AshTemplate.Repo)
  end

  # The tables this repository reads but does not own, in the shape local
  # development and the staging bootstrap run on. Every statement in the file is
  # idempotent, so an already prepared database is left as it is. The file ships
  # inside this application's priv directory and holds only DDL written in this
  # repository, so neither the path nor the statements come from input.
  # sobelow_skip ["SQL.Query", "Traversal.FileModule"]
  def create_shared_tables! do
    :ash_template
    |> Application.app_dir("priv/repo/shared_tables.sql")
    |> File.read!()
    |> String.split(";\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.each(&Ecto.Adapters.SQL.query!(AshTemplate.Repo, &1, []))
  end
end

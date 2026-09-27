defmodule AshTemplate.LocalDatabaseFixture do
  @moduledoc false

  def ensure_human_accounts! do
    validate_target!(current_env(), AshTemplate.Repo.config())
    create_shared_tables!()
    AshTemplate.Repo.migrate!(Application.app_dir(:ash_template, "priv/repo/migrations"))
  end

  def validate_target!(env, repo) when is_list(repo) do
    host = to_string(repo[:hostname])
    database = to_string(repo[:database])

    if env == :dev and host in ["127.0.0.1", "::1"] and String.ends_with?(database, "_dev") do
      :ok
    else
      raise "local human-account fixture refused unsafe database target"
    end
  end

  defp current_env do
    if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
  end

  @doc false
  # The tables this repository reads but does not own, in the shape local
  # development and the staging bootstrap run on. Every statement in the file is
  # idempotent, so an already prepared database is left as it is. The file is
  # shipped inside this application's priv directory and holds only DDL written
  # in this repository, so neither the path nor the statements come from input.
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

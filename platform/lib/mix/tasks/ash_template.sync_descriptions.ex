defmodule Mix.Tasks.AshTemplate.SyncDescriptions do
  @moduledoc """
  Writes each operation's words from its `description` in
  `priv/capabilities.json` (`AshTemplate.Descriptions`) into its browser tool in
  `priv/tool_manifest.json`, its command in `cli/commands.json` and its operation
  in `priv/public/openapi.json`. `--check` writes nothing and fails while a file's
  words are not these.
  """
  use Mix.Task

  alias AshTemplate.Descriptions

  @shortdoc "Writes every surface's operation words from priv/capabilities.json"

  @files [
    manifest: Path.expand("../../../priv/tool_manifest.json", __DIR__),
    commands: Path.expand("../../../../cli/commands.json", __DIR__),
    openapi: Path.expand("../../../priv/public/openapi.json", __DIR__)
  ]

  @impl Mix.Task
  def run([]) do
    for {name, path} <- @files, do: File.write!(path, synced(name, path))
    Mix.shell().info("Wrote every surface's operation words")
  end

  def run(["--check"]) do
    case for(
           {name, path} <- @files,
           File.read!(path) != synced(name, path),
           do: Path.relative_to_cwd(path)
         ) do
      [] -> Mix.shell().info("Every surface's operation words are synchronized")
      stale -> Mix.raise("run mix ash_template.sync_descriptions: #{Enum.join(stale, ", ")}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix ash_template.sync_descriptions [--check]")

  defp synced(name, path) do
    file = path |> File.read!() |> Jason.decode!(objects: :ordered_objects)

    [file |> sync(name) |> Jason.encode!(pretty: true), "\n"]
    |> IO.iodata_to_binary()
  end

  defp sync(manifest, :manifest),
    do: update_in(manifest["tools"], &Enum.map(&1, fn tool -> put(tool, :webmcp) end))

  defp sync(commands, :commands),
    do: update_in(commands["commands"], &Enum.map(&1, fn command -> put(command, :cli) end))

  defp sync(openapi, :openapi),
    do: update_in(openapi["paths"], fn paths -> map_values(paths, &describe/1) end)

  defp describe(methods), do: map_values(methods, &describe_operation/1)

  # A path's `parameters` sit beside its operations.
  defp describe_operation(%Jason.OrderedObject{} = operation),
    do: put_in(operation["description"], Descriptions.text(:http, operation["operationId"]))

  defp describe_operation(parameters), do: parameters

  defp put(entry, surface),
    do: put_in(entry["description"], Descriptions.text(surface, entry["operation_id"]))

  defp map_values(%Jason.OrderedObject{values: values}, fun),
    do: %Jason.OrderedObject{values: Enum.map(values, fn {key, value} -> {key, fun.(value)} end)}
end

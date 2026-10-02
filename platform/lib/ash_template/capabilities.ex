defmodule AshTemplate.Capabilities do
  @moduledoc """
  Every tool the pages offer a browser's own agent, read at compile time from
  `priv/tool_manifest.json`, the file the browser code registers them from.
  """

  @manifest_path Application.app_dir(:ash_template, "priv/tool_manifest.json")
  @external_resource @manifest_path
  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @needs %{"none" => "Nothing"}

  @spec manifest() :: map()
  def manifest, do: @manifest

  @doc "Every tool, in the manifest's order."
  @spec tools() :: [map()]
  def tools, do: @manifest["tools"]

  @doc "Every tool as a Markdown table."
  @spec markdown_table() :: String.t()
  def markdown_table do
    """
    | Tool | Reads | Needs | What it does |
    | --- | --- | --- | --- |
    #{Enum.map_join(tools(), "\n", &"| `#{&1["name"]}` | `#{&1["route"]}` | #{Map.fetch!(@needs, &1["requires"])} | #{&1["description"]} |")}\
    """
  end
end

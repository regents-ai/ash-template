defmodule AshTemplate.Capabilities do
  @moduledoc """
  Every tool the pages offer a browser's own agent, read at compile time from
  `priv/tool_manifest.json`, the file the browser code registers them from.
  """

  @manifest_path Application.app_dir(:ash_template, "priv/tool_manifest.json")
  @external_resource @manifest_path
  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @needs %{
    "none" => "Nothing",
    "siwa" => "A signed request",
    "siwa_and_pairing" => "A signed request and a pairing"
  }

  @spec manifest() :: map()
  def manifest, do: @manifest

  @doc "Every tool, in the manifest's order."
  @spec tools() :: [map()]
  def tools, do: @manifest["tools"]

  @doc "Every tool as a Markdown table, with what each does, for the agent guide."
  @spec markdown_table() :: String.t()
  def markdown_table do
    """
    | Tool | Route | Needs | What it does |
    | --- | --- | --- | --- |
    #{Enum.map_join(tools(), "\n", &"| `#{&1["name"]}` | `#{&1["route"]}` | #{Map.fetch!(@needs, &1["requires"])} | #{&1["description"]} |")}\
    """
  end

  @doc "Every tool's name and what it needs, as a Markdown table for the developer documentation."
  @spec summary_table() :: String.t()
  def summary_table do
    """
    | Tool | Needs |
    | --- | --- |
    #{Enum.map_join(tools(), "\n", &"| `#{&1["name"]}` | #{Map.fetch!(@needs, &1["requires"])} |")}\
    """
  end
end

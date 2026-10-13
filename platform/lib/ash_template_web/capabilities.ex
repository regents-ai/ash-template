defmodule AshTemplateWeb.Capabilities do
  @moduledoc """
  What an agent may do on this site: one row per operation in the OpenAPI
  document, served at `/capabilities.json` and drawn as the agent guide's tables.

  `priv/capabilities.json` says who may run each operation, on what conditions,
  where its person sees it and the earliest regents-cli release with its command.
  The title and address come from `priv/public/openapi.json`, the browser tool
  from `priv/tool_manifest.json` (the file the pages register them from) and the
  command from `cli/commands.json`. The four are checked against each other when
  this module compiles. Whether an operation is open is read from the site's
  switch on every request, never written down. Each agent operation also says,
  in its person's words, what it lets an agent do and what a request to it did,
  which the account page shows.
  """

  alias AshTemplateWeb.Plugs.LaunchGate
  alias AshTemplateWeb.PublicDocuments

  paths = [
    source: Application.app_dir(:ash_template, "priv/capabilities.json"),
    manifest: Application.app_dir(:ash_template, "priv/tool_manifest.json"),
    openapi: Application.app_dir(:ash_template, "priv/public/openapi.json"),
    commands: Path.expand("../../../cli/commands.json", __DIR__)
  ]

  for {_name, path} <- paths, do: @external_resource(path)
  files = Map.new(paths, fn {name, path} -> {name, path |> File.read!() |> Jason.decode!()} end)

  @source files.source
  @manifest files.manifest
  @agents ~w(signed_agent paired_agent)
  @to_person ~w(owner_only wallet)

  openapi =
    for {path, methods} <- files.openapi["paths"],
        {method, %{"operationId" => id} = operation} <- methods,
        into: %{},
        do: {id, %{http: "#{String.upcase(method)} #{path}", title: operation["summary"]}}

  tools = for %{"operation_id" => id} = tool <- @manifest["tools"], into: %{}, do: {id, tool}
  commands = Map.new(files.commands["commands"], &{&1["operation_id"], &1})
  names = fn key -> MapSet.new(@source[key], & &1["name"]) end

  {authorities, conditions, switches} =
    {names.("authorities"), names.("conditions"), names.("switches")}

  unless MapSet.new(@source["operations"], & &1["operation"]) == MapSet.new(Map.keys(openapi)),
    do: raise("priv/capabilities.json must list every OpenAPI operation once")

  @operations (for row <- @source["operations"] do
                 id = row["operation"]
                 %{http: http, title: title} = openapi[id]
                 tool = tools[id]
                 command = commands[id]

                 problem =
                   cond do
                     row["authority"] not in authorities ->
                       "an unknown authority"

                     not Enum.all?(row["conditions"], &(&1 in conditions)) ->
                       "an unknown condition"

                     row["switch"] && row["switch"] not in switches ->
                       "an unknown switch"

                     (row["may"] || row["done"]) && row["authority"] not in @agents ->
                       "words for a person on an operation no agent runs"

                     tool && tool["route"] != http ->
                       "a browser tool on another route"

                     tool &&
                         tool["authentication"] == "siwa_per_request" !=
                           row["authority"] in @agents ->
                       "a browser tool signed differently"

                     tool && !!tool["annotations"]["readOnlyHint"] != (row["effect"] == "read") ->
                       "a browser tool marked read-only differently"

                     command && "#{command["method"]} #{command["path"]}" != http ->
                       "a command on another route"

                     command && command["effect"] != row["effect"] ->
                       "a command with another effect"

                     !!command != !!row["cli_release"] ->
                       "a cli_release without its command, or a command without one"

                     true ->
                       nil
                   end

                 if problem, do: raise("#{id} in priv/capabilities.json has #{problem}")

                 %{
                   operation: id,
                   title: title,
                   effect: row["effect"],
                   authority: row["authority"],
                   conditions: row["conditions"],
                   switch: row["switch"],
                   person_page: row["person_page"],
                   done: row["done"],
                   interfaces: %{
                     browser_tool: tool && tool["name"],
                     hosted_mcp: nil,
                     cli:
                       command && "regents #{files.commands["platform"]} #{command["command"]}",
                     http: http
                   },
                   cli_release: row["cli_release"]
                 }
               end)

  @may @source["operations"] |> Enum.map(& &1["may"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  @doc "What a paired agent may do on this site, in its person's words, a line each."
  @spec may() :: [String.t()]
  def may, do: @may

  @requests (for %{done: done, interfaces: %{http: http}} <- @operations, done do
               [method, path] = String.split(http, " ")
               %{method: method, path: path, words: done}
             end)

  @doc """
  This site's agent requests and what each did, in its person's words, as
  `RegentAgents.Activity.recent/3` takes them.
  """
  @spec requests() :: [RegentAgents.Activity.operation()]
  def requests, do: @requests

  @doc "The whole document, with each operation's gate as the site's switches stand now."
  @spec document() :: map()
  def document do
    %{
      site: "ash-template",
      base_url: PublicDocuments.url(""),
      build: Application.fetch_env!(:ash_template, :build),
      cli: @source["cli"],
      authorities: Enum.map(@source["authorities"], &%{name: &1["name"], words: &1["words"]}),
      conditions: Enum.map(@source["conditions"], &%{name: &1["name"], words: &1["words"]}),
      operations: operations()
    }
  end

  @doc "Every operation, in the source's order, with its gate and what an agent does with it."
  @spec operations() :: [map()]
  def operations do
    Enum.map(@operations, fn row ->
      gate = gate(row.switch)

      row
      |> Map.drop([:switch, :done])
      |> Map.merge(%{gate: gate, agent_use: agent_use(gate, row.authority), last_test: nil})
    end)
  end

  defp gate(nil), do: %{state: "open", reason: nil}

  defp gate("app_surfaces") do
    if LaunchGate.app_surfaces_enabled?(),
      do: %{state: "open", reason: nil},
      else: %{state: "closed", reason: switch_words("app_surfaces")}
  end

  defp switch_words(name), do: Enum.find(@source["switches"], &(&1["name"] == name))["words"]

  defp agent_use(%{state: "closed"}, _authority), do: "closed"
  defp agent_use(_gate, authority) when authority in @to_person, do: "hand_to_person"
  defp agent_use(_gate, _authority), do: "run"

  @doc "Every operation as a Markdown table for the agent guide: who may, and how an agent reaches it."
  @spec markdown_table() :: String.t()
  def markdown_table do
    """
    | Operation | What it does | Who may | Browser tool | Command | For an agent |
    | --- | --- | --- | --- | --- | --- |
    #{Enum.map_join(operations(), "\n", &operation_row/1)}\
    """
  end

  defp operation_row(row) do
    "| `#{row.operation}` | #{row.title} | #{who(row)} | #{code(row.interfaces.browser_tool)} | " <>
      "#{command(row)} | #{use_words(row)} |"
  end

  @doc "Every browser tool and who may run it, as a Markdown table for the developer documentation."
  @spec summary_table() :: String.t()
  def summary_table do
    rows = Map.new(@operations, &{&1.operation, &1})

    """
    | Tool | Operation | Who may |
    | --- | --- | --- |
    #{Enum.map_join(@manifest["tools"], "\n", &tool_row(&1, rows[&1["operation_id"]]))}\
    """
  end

  defp tool_row(tool, nil), do: "| `#{tool["name"]}` | none | #{authority_words("public")} |"

  defp tool_row(tool, row),
    do: "| `#{tool["name"]}` | `#{row.operation}` | #{who(row)} |"

  defp who(row) do
    Enum.join(
      [authority_words(row.authority) | Enum.map(row.conditions, &condition_words/1)],
      " "
    )
  end

  defp authority_words(name),
    do: Enum.find(@source["authorities"], &(&1["name"] == name))["words"]

  defp condition_words(name),
    do: "Needs: " <> Enum.find(@source["conditions"], &(&1["name"] == name))["words"]

  defp use_words(%{agent_use: "run"}), do: "Runs it"

  defp use_words(%{agent_use: "hand_to_person", person_page: page}),
    do: "Hands it to its person at `#{page}`"

  defp use_words(%{agent_use: "closed", gate: gate}), do: "Closed: #{gate.reason}"

  defp command(%{interfaces: %{cli: nil}}), do: "none"
  defp command(row), do: "`#{row.interfaces.cli}` (#{row.cli_release} and later)"

  defp code(nil), do: "none"
  defp code(text), do: "`#{text}`"
end

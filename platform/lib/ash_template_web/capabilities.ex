defmodule AshTemplateWeb.Capabilities do
  @moduledoc """
  What an agent may do on this site: one row per operation in the OpenAPI
  document, and one per tool only the hosted MCP server has, served at
  `/capabilities.json` and drawn as the agent guide's tables.

  `priv/capabilities.json` says who may run each operation, on what conditions,
  where its person sees it and the earliest regents-cli release with its command.
  The title and address come from `priv/public/openapi.json`, the browser tool
  from `priv/tool_manifest.json` (the file the pages register them from) and the
  command from `cli/commands.json`, and the hosted MCP tool from the AshAi `tools`
  block of the operation's domain. These are checked against each other when this
  module compiles: every browser tool must be named after its command, every
  surface an operation leaves out gives a reason, and a hosted tool takes the
  browser tool's input. Each operation's output schema is its success answer in
  the OpenAPI document, its references pointing there. A tool only the hosted MCP
  server has, such as a connected app's identity tools, is named after its
  operation (`getIdentity` is `get_identity`), takes its title from its AshAi tool
  and names its answer's schema among the OpenAPI document's components.
  Whether an operation is open is read from the site's switch on every request,
  never written down. Each agent operation also says,
  in its person's words, what it lets an agent do, which the Agents page shows.
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
  @changes_nothing ~w(read quote)
  @to_person ~w(owner_only wallet)
  @connected_app "connected_app"

  openapi =
    for {path, methods} <- files.openapi["paths"],
        {method, %{"operationId" => id} = operation} <- methods,
        into: %{},
        do: {id, %{http: "#{String.upcase(method)} #{path}", title: operation["summary"]}}

  output_schemas =
    for {_path, methods} <- files.openapi["paths"],
        {_method, %{"operationId" => id, "responses" => responses}} <- methods,
        into: %{} do
      {_status, success} = responses |> Enum.filter(&match?({"2" <> _, _}, &1)) |> Enum.min()
      {id, get_in(success, ["content", "application/json", "schema"])}
    end

  tools = for %{"operation_id" => id} = tool <- @manifest["tools"], into: %{}, do: {id, tool}

  # The tools each domain hands AshAi for hosted MCP, by name, with their title
  # and the input AshAi asks for. The chat assistant's own tools
  # (`AshTemplate.Chat`) are never hosted.
  hosted =
    for domain <- Application.compile_env!(:ash_template, :ash_domains),
        domain != AshTemplate.Chat,
        tool <- AshAi.Info.tools(domain),
        into: %{} do
      action = Ash.Resource.Info.action(tool.resource, tool.action)

      schema =
        AshAi.Tool.Schema.for_action(domain, tool.resource, action, nil, [], strict?: false)

      {Atom.to_string(tool.name), %{input: schema["properties"]["input"], title: tool.title}}
    end

  components = files.openapi["components"]["schemas"]

  # An input's shape for comparing two schemas: each field's type, choices and
  # format, and which fields are required. Words and lengths are left out.
  shape = fn schema ->
    {Map.new(schema["properties"], fn {name, field} ->
       {name, Map.take(field, ~w(type enum format))}
     end), MapSet.new(schema["required"] || [])}
  end

  surface_names = ~w(webmcp hosted_mcp http cli)
  commands = Map.new(files.commands["commands"], &{&1["operation_id"], &1})
  names = fn key -> MapSet.new(@source[key], & &1["name"]) end

  # A browser tool is its command's words, arguments left out, joined and with
  # hyphens turned into underscores: `notes rate-label <id>` is `notes_rate_label`.
  tool_name = fn command ->
    command
    |> String.split(" ")
    |> Enum.reject(&String.starts_with?(&1, "<"))
    |> Enum.join("_")
    |> String.replace("-", "_")
  end

  actors =
    Map.new(
      [{"public", "anonymous"}, {@connected_app, @connected_app}] ++
        Enum.map(@agents, &{&1, "agent"}) ++ Enum.map(@to_person, &{&1, "person"})
    )

  {authorities, conditions, switches} =
    {names.("authorities"), names.("conditions"), names.("switches")}

  listed = Enum.map(@source["operations"], & &1["operation"])

  unless length(listed) == length(Enum.uniq(listed)) and
           MapSet.subset?(MapSet.new(Map.keys(openapi)), MapSet.new(listed)),
         do: raise("priv/capabilities.json must list every OpenAPI operation once")

  @operations (for row <- @source["operations"] do
                 id = row["operation"]
                 # An operation the OpenAPI document leaves out is a tool only the
                 # hosted MCP server has, named after it.
                 hosted_only = !openapi[id] && Macro.underscore(id)
                 hosted_tool = hosted_only && hosted[hosted_only]

                 %{http: http, title: title} =
                   openapi[id] || %{http: nil, title: hosted_tool && hosted_tool.title}

                 tool = tools[id]
                 command = commands[id]
                 surfaces = row["surfaces"]
                 hosted_input = tool && hosted[tool["name"]][:input]
                 browser_input = tool && tool["input_schema"]

                 "#/components/schemas/" <> answer =
                   row["output_schema"]["$ref"] || "#/components/schemas/"

                 problem =
                   cond do
                     hosted_only && !hosted_tool ->
                       "no OpenAPI operation and no hosted tool named after it"

                     hosted_only &&
                         (surfaces["hosted_mcp"] != true or
                            Enum.any?(~w(webmcp http cli), &(surfaces[&1] == true)) or
                            !!(tool || command) or !components[answer]) ->
                       "a hosted-only tool on another surface, or with no answer schema among the components"

                     !hosted_only && Map.has_key?(row, "output_schema") ->
                       "an output_schema beside its OpenAPI operation's own answer"

                     row["authority"] not in authorities ->
                       "an unknown authority"

                     not Enum.all?(row["conditions"], &(&1 in conditions)) ->
                       "an unknown condition"

                     row["switch"] && row["switch"] not in switches ->
                       "an unknown switch"

                     row["may"] && row["authority"] not in @agents ->
                       "words for a person on an operation no agent runs"

                     tool && tool["route"] != http ->
                       "a browser tool on another route"

                     tool &&
                         tool["authentication"] == "siwa_per_request" !=
                           row["authority"] in @agents ->
                       "a browser tool signed differently"

                     tool &&
                         !!tool["annotations"]["readOnlyHint"] !=
                           row["effect"] in @changes_nothing ->
                       "a browser tool marked read-only differently"

                     command && "#{command["method"]} #{command["path"]}" != http ->
                       "a command on another route"

                     command && command["effect"] != row["effect"] ->
                       "a command with another effect"

                     command && command["webmcp"] != (tool && tool["name"]) ->
                       "a command naming another browser tool"

                     tool && command && tool["name"] != tool_name.(command["command"]) ->
                       "a browser tool not named after its command"

                     !!command != (!!row["cli_release"] or row["cli_pending"] == true) ->
                       "a cli_release without its command, or a command without one"

                     Map.keys(surfaces) |> Enum.sort() != Enum.sort(surface_names) or
                         not Enum.all?(
                           Map.values(surfaces),
                           &(&1 == true or (is_binary(&1) and &1 != ""))
                         ) ->
                       "a surface left out with no reason"

                     surfaces["webmcp"] == true != !!tool or surfaces["cli"] == true != !!command or
                         surfaces["http"] == true != !!http ->
                       "a surface listed differently from its tool, command or route"

                     hosted_input && shape.(hosted_input) != shape.(browser_input) ->
                       "hosted input that differs from the browser tool's input"

                     row["authority"] == "public" and
                         (row["fresh_proof"] or row["auth_modes"] != []) ->
                       "a public operation that needs proof"

                     "siwa_request" in row["auth_modes"] != row["authority"] in @agents or
                       row["fresh_proof"] != "siwa_request" in row["auth_modes"] or
                         "site_oauth" in row["auth_modes"] !=
                           (row["authority"] == @connected_app or
                              (row["authority"] in @agents and surfaces["hosted_mcp"] == true)) ->
                       "proof that differs from its authority"

                     row["actor"] != actors[row["authority"]] ->
                       "an actor that differs from its authority"

                     row["retry"] == "operation_key" != !!(tool && tool["operation_id_field"]) ->
                       "an operation-key retry with no operation_id field, or the field with another retry"

                     row["retry"] == "read_safe" != row["effect"] in @changes_nothing ->
                       "a read-safe retry on an operation that changes something, or none on a read"

                     row["context"] != "none" or row["lifecycle"] != "immediate" ->
                       "a context or lifecycle the template does not have"

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
                   interfaces: %{
                     browser_tool: tool && tool["name"],
                     hosted_mcp:
                       if(surfaces["hosted_mcp"] == true, do: hosted_only || tool["name"]),
                     cli:
                       command && "regents #{files.commands["platform"]} #{command["command"]}",
                     http: http
                   },
                   cli_release: row["cli_release"],
                   surfaces: surfaces,
                   auth_modes: row["auth_modes"],
                   fresh_proof: row["fresh_proof"],
                   actor: row["actor"],
                   context: row["context"],
                   retry: row["retry"],
                   lifecycle: row["lifecycle"],
                   output_schema: output_schemas[id] || row["output_schema"]
                 }
               end)

  unless MapSet.new(@operations, & &1.interfaces.hosted_mcp) |> MapSet.delete(nil) ==
           MapSet.new(Map.keys(hosted)),
         do:
           raise(
             "priv/capabilities.json must mark hosted_mcp on exactly the operations whose " <>
               "browser tool, or own name, is an AshAi tool"
           )

  @hosted for row <- @operations,
              name = row.interfaces.hosted_mcp,
              do: String.to_atom(name)

  @doc "The hosted MCP server's tools, by the name AshAi gives each."
  @spec hosted_tools() :: [atom()]
  def hosted_tools, do: @hosted

  @may @source["operations"] |> Enum.map(& &1["may"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  @doc "What a paired agent may do on this site, in its person's words, a line each."
  @spec may() :: [String.t()]
  def may, do: @may

  @doc "The whole document, with each operation's gate as the site's switches stand now."
  @spec document() :: map()
  def document do
    %{
      site: "ash-template",
      base_url: PublicDocuments.url(""),
      build: Application.fetch_env!(:ash_template, :build),
      cli: @source["cli"],
      contract_revision: @source["contract_revision"],
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
      |> Map.drop([:switch])
      |> Map.merge(%{
        gate: gate,
        agent_use: agent_use(gate, row.authority),
        output_schema: to_openapi(row.output_schema),
        last_test: nil
      })
    end)
  end

  # A reference inside the OpenAPI document, pointed at the document itself.
  defp to_openapi(%{"$ref" => "#" <> pointer} = schema),
    do: %{schema | "$ref" => PublicDocuments.url("/openapi.json") <> "#" <> pointer}

  defp to_openapi(schema) when is_map(schema),
    do: Map.new(schema, fn {k, v} -> {k, to_openapi(v)} end)

  defp to_openapi(list) when is_list(list), do: Enum.map(list, &to_openapi/1)
  defp to_openapi(value), do: value

  defp gate(nil), do: %{state: "open", reason: nil}

  defp gate("connected_apps") do
    if AshTemplate.OAuth.enabled?(),
      do: %{state: "open", reason: nil},
      else: %{state: "closed", reason: switch_words("connected_apps")}
  end

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
    | Operation | Action | Allowed | Browser tool | Command | Surfaces | Proof | For an agent |
    | --- | --- | --- | --- | --- | --- | --- | --- |
    #{Enum.map_join(operations(), "\n", &operation_row/1)}\
    """
  end

  defp operation_row(row) do
    "| `#{row.operation}` | #{row.title} | #{who(row)} | #{code(row.interfaces.browser_tool)} | " <>
      "#{command(row)} | #{surface_words(row.surfaces)} | #{proof_words(row)} | #{use_words(row)} |"
  end

  @surface_words [webmcp: "WebMCP", hosted_mcp: "MCP", http: "HTTP", cli: "CLI"]

  defp surface_words(surfaces) do
    @surface_words
    |> Enum.filter(fn {name, _words} -> surfaces[Atom.to_string(name)] == true end)
    |> Enum.map_join(", ", &elem(&1, 1))
  end

  defp proof_words(%{authority: @connected_app}),
    do: "The app's connection to its person's account"

  defp proof_words(%{fresh_proof: true, auth_modes: modes}) do
    if "site_oauth" in modes,
      do: "A new signature on every request, or at MCP its person's connected app, once paired",
      else: "A new signature on every request"
  end

  # Every call at /mcp carries a credential, so a read anyone may make elsewhere
  # needs one there.
  defp proof_words(%{auth_modes: [], surfaces: %{"hosted_mcp" => true}}),
    do: "None, except at MCP: your agent's signature or connected app"

  defp proof_words(%{auth_modes: []}), do: "None"
  defp proof_words(_row), do: "Its person's sign-in"

  @doc "Every browser tool and who may run it, as a Markdown table for the developer documentation."
  @spec summary_table() :: String.t()
  def summary_table do
    rows = Map.new(@operations, &{&1.operation, &1})

    """
    | Tool | Operation | Allowed |
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
  defp command(%{cli_release: nil} = row), do: "`#{row.interfaces.cli}` (not yet released)"

  defp command(row), do: "`#{row.interfaces.cli}` (#{row.cli_release} and later)"

  defp code(nil), do: "none"
  defp code(text), do: "`#{text}`"
end

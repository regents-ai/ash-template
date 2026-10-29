defmodule AshTemplate.Descriptions do
  @moduledoc """
  Each operation's words on every surface, from its one `description` in
  `priv/capabilities.json`: its browser tool's in `priv/tool_manifest.json`, its
  command's in `cli/commands.json`, its OpenAPI operation's in
  `priv/public/openapi.json` and its hosted MCP tool's, which the domains' `tools`
  blocks take from `hosted/1`. Each surface adds the same few words to it: who may
  run it and whether it changes anything, and on a browser tool how it is signed.
  A connected app's identity tools keep the shared library's words.

  `mix ash_template.sync_descriptions` writes them into the three files, and
  `--check` (in `mix precommit`) fails while a file's words are not these.
  """

  paths = [
    capabilities: Application.app_dir(:ash_template, "priv/capabilities.json"),
    manifest: Application.app_dir(:ash_template, "priv/tool_manifest.json")
  ]

  for {_name, path} <- paths, do: @external_resource(path)
  files = Map.new(paths, fn {name, path} -> {name, path |> File.read!() |> Jason.decode!()} end)

  @rows for row <- files.capabilities["operations"],
            Map.has_key?(row, "description"),
            into: %{},
            do: {row["operation"], row}

  # A hosted tool shares its browser tool's name.
  @operations Map.new(files.manifest["tools"], &{&1["name"], &1["operation_id"]})

  @changes_nothing ~w(read quote)
  @signers ~w(signed_agent paired_agent)
  @signed "Signed: your browser host signs it with your own agent key, as regents browser does."

  @type surface :: :webmcp | :hosted_mcp | :cli | :http

  @doc "The words of `operation` on `surface`."
  @spec text(surface(), String.t()) :: String.t()
  def text(surface, operation) do
    %{"description" => words, "authority" => authority, "effect" => effect} =
      Map.fetch!(@rows, operation)

    [words, access(surface, authority, effect in @changes_nothing), signed(surface, authority)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc "The words of the hosted MCP tool `name`, for its `description` in a domain's `tools` block."
  @spec hosted(atom()) :: String.t()
  def hosted(name), do: text(:hosted_mcp, Map.fetch!(@operations, Atom.to_string(name)))

  # Every hosted call is signed, so a public read there only changes nothing.
  defp access(:hosted_mcp, "public", _changes_nothing), do: "Changes nothing."
  defp access(_surface, "public", _changes_nothing), do: "No sign-in; changes nothing."
  defp access(_surface, "paired_agent", true), do: "Changes nothing. Needs a pairing."
  defp access(_surface, "paired_agent", false), do: "Needs a pairing."
  defp access(_surface, "signed_agent", true), do: "Works before pairing; changes nothing."
  defp access(_surface, _authority, true), do: "Changes nothing."
  defp access(_surface, _authority, false), do: nil

  defp signed(:webmcp, authority) when authority in @signers, do: @signed
  defp signed(_surface, _authority), do: nil
end

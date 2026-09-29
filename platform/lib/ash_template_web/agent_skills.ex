defmodule AshTemplateWeb.AgentSkills do
  @moduledoc """
  The build skills this site serves, read from the repository's `skills/` folder
  when the app compiles, so `skills/` stays their one source.

  Only the skills named in `@names` are served, and only the files they held at
  compile time: a request looks its path up in a fixed table, and no path from a
  request reaches the file system.

  They follow Agent Skills Discovery v0.2.0
  (https://github.com/cloudflare/agent-skills-discovery-rfc). The index at
  `/.well-known/agent-skills/index.json` lists each skill with its `SKILL.md`
  description and a zip of its folder (`SKILL.md` at the zip's root) with that
  zip's sha256 digest. Each file is also served on its own at
  `/.well-known/agent-skills/<name>/<path>`, so the links between skills resolve.
  The zips are built with fixed dates and modes, so the same files always give
  the same digest.

  The showcase setting (`AshTemplateWeb.Showcase`) decides who can fetch them.
  """

  @root Path.expand("../../../skills", __DIR__)
  @names ~w(ash-stack ash-backend ash-data ash-frontend ash-security ash-testing ash-webmcp animejs onchain-buttons chain-events payments)
  @base "/.well-known/agent-skills"
  @schema "https://schemas.agentskills.io/discovery/0.2.0/schema.json"
  @types %{
    ".md" => "text/markdown",
    ".py" => "text/x-python",
    ".yaml" => "application/yaml"
  }
  @pattern Path.join(@root, "{#{Enum.join(@names, ",")}}/**")

  paths = Path.wildcard(@pattern)
  @paths_hash :erlang.md5(paths)
  files = Enum.filter(paths, &File.regular?/1)
  for file <- files, do: @external_resource(file)

  # A file added to or removed from a served skill rebuilds this module.
  def __mix_recompile__?, do: :erlang.md5(Path.wildcard(@pattern)) != @paths_hash

  epoch = {{1980, 1, 1}, {0, 0, 0}}

  skills =
    for name <- @names do
      folder = Path.join(@root, name)
      skill_md = File.read!(Path.join(folder, "SKILL.md"))

      [_, frontmatter] = Regex.run(~r/\A---\n(.*?)\n---\n/s, skill_md)
      [_, ^name] = Regex.run(~r/^name: (.+)$/m, frontmatter)
      [_, description] = Regex.run(~r/^description: (.+)$/m, frontmatter)

      entries =
        for path <- files, String.starts_with?(path, folder <> "/") do
          relative = Path.relative_to(path, folder)
          body = File.read!(path)
          type = Map.fetch!(@types, Path.extname(relative))
          {relative, type, body}
        end

      zip_entries =
        for {relative, _type, body} <- entries do
          stat = %File.Stat{
            size: byte_size(body),
            type: :regular,
            access: :read,
            atime: epoch,
            mtime: epoch,
            ctime: epoch,
            mode: 0o100644,
            links: 1,
            major_device: 0,
            minor_device: 0,
            inode: 0,
            uid: 0,
            gid: 0
          }

          {String.to_charlist(relative), body, File.Stat.to_record(stat)}
        end

      {:ok, {_, zip}} = :zip.create(~c"#{name}.zip", zip_entries, [:memory])

      %{
        name: name,
        description: description,
        zip: zip,
        files: entries
      }
    end

  @index Jason.encode!(
           %{
             "$schema" => @schema,
             "skills" =>
               for skill <- skills do
                 %{
                   "name" => skill.name,
                   "type" => "archive",
                   "description" => skill.description,
                   "url" => "#{@base}/#{skill.name}.zip",
                   "digest" =>
                     "sha256:" <> Base.encode16(:crypto.hash(:sha256, skill.zip), case: :lower)
                 }
               end
           },
           pretty: true
         )

  served =
    for skill <- skills, reduce: %{"index.json" => {"application/json", @index}} do
      served ->
        files =
          Map.new(skill.files, fn {relative, type, body} ->
            {"#{skill.name}/#{relative}", {type, body}}
          end)

        served
        |> Map.put("#{skill.name}.zip", {"application/zip", skill.zip})
        |> Map.merge(files)
    end

  @served served

  @skills Enum.map(skills, &Map.take(&1, [:name, :description]))

  @doc "The address every served path hangs from."
  def base, do: @base

  @doc "Each served skill's name and `SKILL.md` description, in the listed order."
  def skills, do: @skills

  @doc "The content type and body served at `path` under `base/0`, or `:error`."
  def fetch(path), do: Map.fetch(@served, path)
end

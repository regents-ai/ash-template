# Fails unless every shared library comes from a pinned, inspectable commit of its
# own repository and every required security fix is present.
#
# Reads the required-fixes registry (ash-template's security/required-fixes.json) on
# standard input; the one argument names the registry revision for the report. Run
# from the platform folder after `mix deps.get` (the Makefile's check-required-fixes
# fetches both this script and the registry from ash-template's main branch):
#
#     elixir check_required_fixes.exs REVISION < required-fixes.json
#
# "managed" lists each shared library: its app, its one repository URL and its folder
# there. A managed library must be a git dependency on exactly that URL and folder,
# pinned with `ref:` to a full commit whose history is fetched. Local folders,
# vendored copies, other URLs and unlisted libraries from a shared repository fail,
# and so do libraries from one repository pinned at different commits. The one
# local folder allowed is the library's own folder in its own repository (Regents
# uses identity/ from the same commit).
# A "git" fix must be in the pinned history of each listed app the site uses; a
# "hex" fix sets the Hex versions a package may be locked at, as an Elixir version
# requirement (">= 3.34.3", "== 2.13.0"). Dependencies of every
# environment are checked, not only the one the check runs in.

[revision] = System.argv()
Mix.start()
Mix.Hex.start()
Code.compile_file("mix.exs")

%{"managed" => managed, "fixes" => fixes} = JSON.decode!(IO.read(:stdio, :eof))
managed = Map.new(managed, &{&1["app"], &1})

{:ok, quoted} = Code.string_to_quoted(File.read!("mix.lock"), emit_warnings: false)
{lock, _binding} = Code.eval_quoted(quoted)
lock = Map.new(lock, fn {app, entry} -> {Atom.to_string(app), entry} end)

deps = Map.new(Mix.Dep.Converger.converge(env: nil), &{Atom.to_string(&1.app), &1})

same_repository = fn url ->
  url
  |> String.downcase()
  |> String.replace(
    ~r{^(git@github\.com:|ssh://git@github\.com/|git://github\.com/|http://github\.com/)},
    "https://github.com/"
  )
  |> String.trim_trailing("/")
  |> String.trim_trailing(".git")
end

shared_repositories =
  managed |> Map.values() |> MapSet.new(&same_repository.(&1["repository"]))

folder = fn app -> Path.relative_to_cwd(deps[app].opts[:dest]) end
git = fn app, args -> System.cmd("git", ["-C", folder.(app) | args], stderr_to_stdout: true) end

own_folder? = fn app ->
  %{"repository" => repository, "sparse" => sparse} = managed[app]

  with {top, 0} <- System.cmd("git", ["rev-parse", "--show-toplevel"], stderr_to_stdout: true),
       {origin, 0} <- System.cmd("git", ["remote", "get-url", "origin"], stderr_to_stdout: true) do
    same_repository.(String.trim(origin)) == same_repository.(repository) and
      Path.expand(deps[app].opts[:dest]) == Path.join(String.trim(top), sparse)
  else
    _not_a_checkout -> false
  end
end

pinned_git = fn app, commit, opts, sparse ->
  cond do
    opts[:sparse] != sparse ->
      ["#{app} uses the folder #{inspect(opts[:sparse])}; it must be #{inspect(sparse)}"]

    opts[:ref] != commit or not (commit =~ ~r/\A[0-9a-f]{40}\z/) ->
      ["#{app} must be pinned with ref: set to a full commit, not a branch or tag"]

    git.(app, ["rev-parse", "HEAD"]) != {commit <> "\n", 0} ->
      [
        "#{app}'s checkout is not at its locked commit #{String.slice(commit, 0, 7)}; run mix deps.get"
      ]

    git.(app, ["rev-parse", "--is-shallow-repository"]) != {"false\n", 0} ->
      [
        "#{app}'s commit history is missing (shallow checkout); remove depth:, then run mix deps.clean #{app} and mix deps.get"
      ]

    true ->
      []
  end
end

provenance = fn
  app, %{scm: Mix.SCM.Path} ->
    if own_folder?.(app),
      do: [],
      else: [
        "#{app} loads from a local folder (#{folder.(app)}); shared code must come from a pinned git commit"
      ]

  app, %{scm: Mix.SCM.Git, opts: opts} ->
    %{"repository" => repository, "sparse" => sparse} = managed[app]

    case {opts[:git], lock[app]} do
      {^repository, {:git, ^repository, commit, locked}} ->
        if Keyword.take(locked, [:ref, :sparse]) == Keyword.take(opts, [:ref, :sparse]),
          do: pinned_git.(app, commit, opts, sparse),
          else: ["#{app}'s mix.lock entry does not match mix.exs; run mix deps.get"]

      {^repository, _entry} ->
        ["#{app}'s mix.lock entry does not match mix.exs; run mix deps.get"]

      {url, _entry} ->
        if same_repository.(url) == same_repository.(repository),
          do: ["#{app} names its repository as #{url}; write exactly #{repository}"],
          else: ["#{app} comes from #{url}, not #{repository}"]
    end

  app, %{scm: scm} ->
    ["#{app} comes from #{inspect(scm)}, not its shared repository"]
end

stray = fn
  app, %{scm: Mix.SCM.Path} ->
    [
      "#{app} loads from a local folder (#{folder.(app)}); use a Hex package or a pinned git commit"
    ]

  app, %{scm: Mix.SCM.Git, opts: opts} ->
    if MapSet.member?(shared_repositories, same_repository.(opts[:git])),
      do: ["#{app} comes from shared repository #{opts[:git]} but is not listed in the registry"],
      else: []

  _app, _dep ->
    []
end

provenance_problems =
  Map.new(deps, fn {app, dep} ->
    {app, if(Map.has_key?(managed, app), do: provenance.(app, dep), else: stray.(app, dep))}
  end)

inspectable =
  for {app, []} <- provenance_problems, Map.has_key?(managed, app), into: MapSet.new(), do: app

mixed_commit_problems =
  for {repository, apps} <-
        inspectable |> Enum.filter(&lock[&1]) |> Enum.group_by(&managed[&1]["repository"]),
      commits = Enum.map(apps, &"#{&1} #{String.slice(elem(lock[&1], 2), 0, 7)}"),
      apps |> Enum.map(&elem(lock[&1], 2)) |> Enum.uniq() |> length() > 1,
      do:
        "#{repository} is pinned at more than one commit (#{Enum.join(commits, ", ")}); pin all its libraries to one commit"

fix_problems =
  Enum.flat_map(fixes, fn
    %{"kind" => "git", "commit" => fix, "apps" => apps} = entry ->
      for app <- apps,
          MapSet.member?(inspectable, app),
          elem(git.(app, ["merge-base", "--is-ancestor", fix, "HEAD"]), 1) != 0,
          do: "#{app} is pinned without #{entry["id"]}: #{entry["summary"]}"

    %{"kind" => "hex", "package" => package, "requirement" => requirement} = entry ->
      case {deps[package], lock[package]} do
        {nil, _entry} ->
          []

        {_dep, {:hex, _name, version, _hash, _managers, _deps, _repo, _outer}} ->
          if not Version.match?(version, requirement),
            do: [
              "#{package} #{version} is outside #{requirement} (#{entry["id"]}): #{entry["summary"]}"
            ],
            else: []

        {_dep, _entry} ->
          ["#{package} is not locked as a Hex package, so #{entry["id"]} cannot be checked"]
      end
  end)

case Enum.flat_map(provenance_problems, &elem(&1, 1)) ++ mixed_commit_problems ++ fix_problems do
  [] ->
    used = inspectable |> Enum.sort() |> Enum.join(", ")

    IO.puts(
      "Required fixes #{revision}: every shared library is pinned and inspectable (#{used}) and every required fix is present."
    )

  problems ->
    IO.puts(:stderr, "Required fixes #{revision}:")
    Enum.each(problems, &IO.puts(:stderr, "  " <> &1))
    System.halt(1)
end

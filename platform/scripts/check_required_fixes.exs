# Fails unless every shared library comes from a pinned, inspectable commit of its
# own repository and every required security fix is present.
#
# Reads the required-fixes registry (ash-template's security/required-fixes.json) on
# standard input; the one argument names the registry revision for the report. Run
# from the platform folder after `mix deps.get` (the Makefile's check-required-fixes
# fetches both this script and the registry from ash-template's main branch):
#
#     mix run --no-start --no-compile --no-deps-check check_required_fixes.exs REVISION
#
# "managed" lists each shared library: its app, its one repository URL and its folder
# there. A managed library must be a git dependency on exactly that URL and folder,
# pinned with `ref:` to a full commit whose history is fetched. Local folders,
# vendored copies, other URLs and unlisted libraries from a shared repository fail,
# and so do libraries from one repository pinned at different commits.
# A "git" fix must be in the pinned history of each listed app the site uses; a
# "hex" fix sets the lowest allowed Hex version of a package. Dependencies of every
# environment are checked, not only the one the check runs in.

[revision] = System.argv()
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
    [
      "#{app} loads from a local folder (#{folder.(app)}); shared code must come from a pinned git commit"
    ]

  app, %{scm: Mix.SCM.Git} ->
    %{"repository" => repository, "sparse" => sparse} = managed[app]

    case lock[app] do
      {:git, ^repository, commit, opts} ->
        pinned_git.(app, commit, opts, sparse)

      {:git, url, _commit, _opts} ->
        if same_repository.(url) == same_repository.(repository),
          do: ["#{app} names its repository as #{url}; write exactly #{repository}"],
          else: ["#{app} comes from #{url}, not #{repository}"]

      nil ->
        ["#{app} is missing from mix.lock; run mix deps.get"]
    end

  app, %{scm: scm} ->
    ["#{app} comes from #{inspect(scm)}, not its shared repository"]
end

stray = fn
  app, %{scm: Mix.SCM.Path} ->
    [
      "#{app} loads from a local folder (#{folder.(app)}); use a Hex package or a pinned git commit"
    ]

  app, %{scm: Mix.SCM.Git} ->
    {:git, url, _commit, _opts} = lock[app]

    if MapSet.member?(shared_repositories, same_repository.(url)),
      do: ["#{app} comes from shared repository #{url} but is not listed in the registry"],
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
  for {repository, apps} <- Enum.group_by(inspectable, &managed[&1]["repository"]),
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

    %{"kind" => "hex", "package" => package, "minimum" => minimum} = entry ->
      case {deps[package], lock[package]} do
        {nil, _entry} ->
          []

        {_dep, {:hex, _name, version, _hash, _managers, _deps, _repo, _outer}} ->
          if Version.compare(version, minimum) == :lt,
            do: [
              "#{package} #{version} is older than #{minimum} and lacks #{entry["id"]}: #{entry["summary"]}"
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

# Fails when a pinned shared library lacks a required security fix.
#
# Reads the required-fixes list (the template's security/required-fixes.json) on
# standard input and checks every git dependency in mix.lock against it. A fix
# applies to a dependency from the same repository whose sparse folder starts
# with one of the fix's packages. The dependency's pinned commit must contain the
# fix commit. Run from the platform folder after `mix deps.get`.

%{"fixes" => fixes} = JSON.decode!(IO.read(:stdio, :eof))
{:ok, quoted} = Code.string_to_quoted(File.read!("mix.lock"), emit_warnings: false)
{lock, _binding} = Code.eval_quoted(quoted)

pinned =
  for {name, {:git, repository, commit, opts}} <- lock,
      do: %{name: name, repository: repository, commit: commit, sparse: opts[:sparse] || ""}

contains? = fn dep, fix ->
  {_out, status} =
    System.cmd("git", ["-C", "deps/#{dep.name}", "merge-base", "--is-ancestor", fix, dep.commit],
      stderr_to_stdout: true
    )

  status == 0
end

missing =
  for fix <- fixes,
      dep <- pinned,
      dep.repository == fix["repository"],
      Enum.any?(fix["packages"], &String.starts_with?(dep.sparse, &1)),
      not contains?.(dep, fix["commit"]),
      do: "#{dep.name} is pinned at #{String.slice(dep.commit, 0, 7)} without #{fix["id"]}: #{fix["summary"]}"

case missing do
  [] ->
    IO.puts("Every required security fix is in the pinned shared libraries.")

  _ ->
    Enum.each(missing, &IO.puts(:stderr, &1))
    System.halt(1)
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AshTemplate.Repo, :manual)
# Every run starts from the rows migrations put there, whatever an earlier run left.
AshTemplate.RealCommits.empty!()

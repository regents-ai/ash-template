ExUnit.start(exclude: [external: true])
AshTemplate.LocalDatabaseFixture.ensure_human_accounts!()
Ecto.Adapters.SQL.Sandbox.mode(AshTemplate.Repo, :manual)

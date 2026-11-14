# LiveViewTest's render_async/2 and assert_receive wait this long by default. Under
# load from other work on the same machine, ExUnit's 100 ms is too short.
ExUnit.start(assert_receive_timeout: 2_000)
Ecto.Adapters.SQL.Sandbox.mode(AshTemplate.Repo, :manual)
# Every run starts from the rows migrations put there, whatever an earlier run left.
AshTemplate.RealCommits.empty!()

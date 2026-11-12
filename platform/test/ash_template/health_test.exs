defmodule AshTemplate.HealthTest do
  # Invariant: the health answer says when a release carries a migration its
  # database has not applied, and still answers 200, so the host keeps serving.
  use ExUnit.Case, async: true
  import Plug.Test

  alias AshTemplate.Repo

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  defp health do
    conn = AshTemplateWeb.Endpoint.call(conn(:get, "/api/v1/health"), [])
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  test "a database with every migration applied says so" do
    assert AshTemplate.Health.migrations_applied?()
    assert {200, %{"status" => "ok", "migrations_applied" => true}} = health()
  end

  test "a migration the database has not recorded leaves the answer at 200 and says so" do
    # Forget the newest applied migration inside this test's own transaction.
    Ecto.Adapters.SQL.query!(
      Repo,
      "DELETE FROM ash_template_app.schema_migrations WHERE version = (SELECT max(version) FROM ash_template_app.schema_migrations)",
      []
    )

    refute AshTemplate.Health.migrations_applied?()
    assert {200, %{"status" => "ok", "migrations_applied" => false}} = health()
  end
end

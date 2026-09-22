defmodule AshTemplate.LocalDatabaseFixtureTest do
  use ExUnit.Case, async: true

  alias AshTemplate.LocalDatabaseFixture

  test "accepts only loopback dev and test database targets" do
    assert :ok =
             LocalDatabaseFixture.validate_target!(:dev,
               hostname: "127.0.0.1",
               database: "ash_template_dev"
             )

    assert :ok =
             LocalDatabaseFixture.validate_target!(:test,
               hostname: "::1",
               database: "ash_template_test"
             )

    for {env, host, database} <- [
          {:prod, "127.0.0.1", "ash_template_dev"},
          {:dev, "db.internal", "ash_template_dev"},
          {:dev, "localhost", "ash_template_dev"},
          {:dev, "127.0.0.1", "ash_template"}
        ] do
      assert_raise RuntimeError, ~r/refused unsafe database target/, fn ->
        LocalDatabaseFixture.validate_target!(env, hostname: host, database: database)
      end
    end
  end
end

defmodule AshTemplate.HealthBusyTest do
  # Invariant: /healthz never waits for a connection and never marks the machine
  # down because its pool is busy. No connection free soon after the database
  # last answered is a busy, healthy site; no connection free when the database
  # has not answered since the machine started is a database that does not
  # answer. A request the pool drops from its queue is counted.
  use ExUnit.Case, async: false
  import Plug.Test

  alias AshTemplate.Repo

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  # The holder keeps the only connection until the check has answered, so a
  # check that waited for it would never answer.
  test "no connection free is still a healthy site, answered at once" do
    holding = hold_every_connection()

    assert {200, "ok"} = healthz()

    release(holding)
  end

  test "no connection free and no answer since the machine started is down" do
    holding = hold_every_connection()
    # As a machine that has just started: nothing has answered yet.
    :ok = :telemetry.detach(AshTemplate.Health)
    :ok = AshTemplate.Health.attach()

    assert {503, "unavailable"} = healthz()

    release(holding)
  end

  test "a request the pool drops from its queue is counted" do
    holding = hold_every_connection()
    before = refused_total()

    assert {:error, %DBConnection.ConnectionError{reason: :queue_timeout}} =
             Repo.query("SELECT 1")

    assert refused_total() == before + 1

    release(holding)
  end

  # The test's one connection, in a transaction that has begun, so the pool has
  # nothing to lend until it is released.
  defp hold_every_connection do
    test = self()

    holder =
      spawn_link(fn ->
        Repo.transaction(fn ->
          send(test, :holding)

          receive do
            :release -> :ok
          end
        end)

        send(test, :released)
      end)

    assert_receive :holding
    holder
  end

  defp release(holder) do
    send(holder, :release)
    assert_receive :released
  end

  defp healthz do
    conn = AshTemplateWeb.Endpoint.call(conn(:get, "/healthz"), [])
    {conn.status, conn.resp_body}
  end

  defp refused_total do
    case Regex.run(
           ~r/^health_db_checkout_refused_total (\d+)/m,
           AshTemplateWeb.Telemetry.scrape()
         ) do
      [_line, count] -> String.to_integer(count)
      nil -> 0
    end
  end
end

defmodule AshTemplate.SavedErrorsTest do
  # Invariant: a fault that repeats on every request is saved at most ten times a
  # minute on a machine, and a checkout the pool refused is never saved, since
  # saving it would take a connection from the pool that just refused one.
  use ExUnit.Case, async: false

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  test "one fault repeating is saved ten times a minute, and a different fault still is" do
    saved = for _ <- 1..12, do: fault(:repeating)

    assert Enum.count(saved, &match?(%ErrorTracker.Occurrence{}, &1)) == 10
    assert Enum.take(saved, -2) == [:noop, :noop]
    assert %ErrorTracker.Occurrence{} = fault(:other)
  end

  test "a checkout the pool refused is not saved" do
    refusal =
      DBConnection.ConnectionError.exception(
        "connection not available and request was dropped from queue after 1000ms",
        :queue_timeout
      )

    assert :noop = report(refusal)
    # As Ash wraps it when an action's read was refused.
    assert :noop = report(Ash.Error.to_error_class(refusal))
  end

  # Two kinds of error, so the tracker groups each as a fault of its own.
  defp fault(:repeating), do: report(RuntimeError.exception("repeating #{unique()}"))
  defp fault(:other), do: report(ArgumentError.exception("other #{unique()}"))

  defp report(exception) do
    raise exception
  rescue
    raised -> ErrorTracker.report(raised, __STACKTRACE__)
  end

  defp unique, do: System.unique_integer([:positive])
end

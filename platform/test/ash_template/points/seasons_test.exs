defmodule AshTemplate.Points.SeasonsTest do
  # Invariant: Points runs in the configured number of 30-day seasons, back to back
  # from the start. Before a start is set they have no dates; at any moment at most
  # one is running, with the days left in it; after the last, all have ended.
  use ExUnit.Case, async: false

  alias AshTemplate.Points.Seasons

  @start ~U[2027-01-10 12:00:00Z]

  setup do
    previous = Application.get_env(:regent_points, :starts_at)
    on_exit(fn -> Application.put_env(:regent_points, :starts_at, previous) end)
  end

  test "before a start is set, every season is still to come, with no dates" do
    Application.put_env(:regent_points, :starts_at, nil)
    seasons = Seasons.at(~U[2027-03-01 00:00:00Z])

    assert length(seasons) == Seasons.count()
    assert Enum.all?(seasons, &(&1.state == :upcoming and &1.starts_at == nil and &1.ends_at == nil))
    assert Seasons.phase(seasons) == :before
  end

  test "from a start, each season follows the last for 30 days" do
    Application.put_env(:regent_points, :starts_at, @start)

    assert [
             %{season: 1, starts_at: ~U[2027-01-10 12:00:00Z], ends_at: ~U[2027-02-09 12:00:00Z]},
             %{season: 2, starts_at: ~U[2027-02-09 12:00:00Z], ends_at: ~U[2027-03-11 12:00:00Z]},
             %{season: 3, starts_at: ~U[2027-03-11 12:00:00Z], ends_at: ~U[2027-04-10 12:00:00Z]}
           ] = Seasons.at(@start)
  end

  test "the running season and its days left follow the clock" do
    Application.put_env(:regent_points, :starts_at, @start)

    assert states(DateTime.add(@start, -1, :second)) == {:before, [:upcoming, :upcoming, :upcoming], nil}
    assert states(@start) == {:running, [:running, :upcoming, :upcoming], 30}
    # Part of a day left counts as a day.
    assert states(~U[2027-02-09 11:00:00Z]) == {:running, [:running, :upcoming, :upcoming], 1}
    assert states(~U[2027-02-09 12:00:00Z]) == {:running, [:ended, :running, :upcoming], 30}
    assert states(~U[2027-03-20 12:00:00Z]) == {:running, [:ended, :ended, :running], 21}
    assert states(~U[2027-04-10 12:00:00Z]) == {:ended, [:ended, :ended, :ended], nil}
  end

  defp states(now) do
    seasons = Seasons.at(now)
    running = Enum.find(seasons, &(&1.state == :running))
    {Seasons.phase(seasons), Enum.map(seasons, & &1.state), running && running.days_left}
  end
end

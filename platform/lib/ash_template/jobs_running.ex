defmodule AshTemplate.JobsRunning do
  @moduledoc """
  How many background jobs this server is running right now, for the bottom bar.
  Oban's own telemetry says when each job starts and ends; the count lives in
  one shared counter, and every change is published on `topic/0`, so open pages
  show it without asking the database.
  """

  @topic "jobs_running"
  @events [[:oban, :job, :start], [:oban, :job, :stop], [:oban, :job, :exception]]

  @doc "Starts counting. Called once as the site starts, before Oban."
  def attach do
    :persistent_term.put(__MODULE__, :counters.new(1, [:write_concurrency]))
    :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)
  end

  @doc "The number of jobs running on this server now."
  def count, do: :counters.get(:persistent_term.get(__MODULE__), 1)

  @doc "The topic each new count is published on, as `{:jobs_running, count}`."
  def topic, do: @topic

  @doc false
  def handle_event([:oban, :job, event], _measurements, _metadata, _config) do
    :counters.add(:persistent_term.get(__MODULE__), 1, if(event == :start, do: 1, else: -1))
    Phoenix.PubSub.broadcast(AshTemplate.PubSub, @topic, {:jobs_running, count()})
  end
end

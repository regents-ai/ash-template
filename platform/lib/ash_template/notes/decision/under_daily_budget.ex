defmodule AshTemplate.Notes.Decision.UnderDailyBudget do
  @moduledoc """
  Holds while the site has asked Jev fewer questions today (UTC) than its daily
  number (`AshTemplate.Notes.Labels.daily_questions/0`).

  Each decision is one question. The caller takes `lock/0` in its transaction
  first, so two saves cannot both take the last question of the day.
  """

  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias AshTemplate.Notes.{Decision, Labels}

  @lock_key :erlang.phash2({__MODULE__, :daily_budget})

  @impl true
  def describe(_opts), do: "the site has questions left today"

  @impl true
  def match?(_actor, _context, _opts) do
    today = DateTime.new!(Date.utc_today(), ~T[00:00:00])

    # The budget is the whole site's, so every account's questions count, not
    # only the ones this actor may read. Only the number leaves this function.
    Decision
    |> Ash.Query.filter(inserted_at >= ^today)
    |> Ash.count!(authorize?: false) < Labels.daily_questions()
  end

  @doc "Takes the budget's lock until the current transaction ends."
  @spec lock() :: :ok
  def lock do
    AshTemplate.Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])
    :ok
  end
end

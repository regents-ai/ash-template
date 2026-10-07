defmodule AshTemplate.Notes.Decision.UnderDailyBudget do
  @moduledoc """
  Holds while the site has asked Jev fewer questions today (UTC) than its daily
  number (`AshTemplate.Notes.Labels.daily_questions/0`), and the actor's saves
  fewer than one person's share (`person_daily_questions/0`), so one person
  cannot use up everyone's labels.

  Each decision is one question. The caller takes `lock/0` in its transaction
  first, so two saves cannot both take the last question of the day.
  """

  use Ash.Policy.SimpleCheck

  require Ash.Query

  alias AshTemplate.Notes.{Decision, Labels}

  @lock_key :erlang.phash2({__MODULE__, :daily_budget})

  @impl true
  def describe(_opts), do: "the site and this person have questions left today"

  @impl true
  def match?(%{human_account_id: account}, _context, _opts) do
    today =
      Decision
      |> Ash.Query.filter(inserted_at >= ^DateTime.new!(Date.utc_today(), ~T[00:00:00]))

    # The budget is the whole site's, so every account's questions count, not
    # only the ones this actor may read. Only the numbers leave this function.
    Ash.count!(today, authorize?: false) < Labels.daily_questions() and
      today
      |> Ash.Query.filter(human_account_id == ^account)
      |> Ash.count!(authorize?: false) < Labels.person_daily_questions()
  end

  def match?(_actor, _context, _opts), do: false

  @doc "Takes the budget's lock until the current transaction ends."
  @spec lock() :: :ok
  def lock do
    AshTemplate.Repo.query!("SELECT pg_advisory_xact_lock($1)", [@lock_key])
    :ok
  end
end

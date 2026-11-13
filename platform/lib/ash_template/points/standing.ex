defmodule AshTemplate.Points.Standing do
  @moduledoc """
  One account's Points as its page and its paired agent show them: the shared
  library's summary (`RegentPoints.summary/1`) with two things this site adds.

    * `seasons`: each season (`AshTemplate.Points.Seasons`) with what the
      account earned in it once it has begun (`earned_micro`, its entries in the
      season summed under the account's own read) and the NFT bonus added at its
      end (`bonus`, the library's period bonus, nil until the tally).
    * `at_start`: before the start, the start rules this site counts
      (`RegentPoints.Rules.start_rules/0`) whose source here finds the account
      already has what earns them, through each source's `held/2` beside the
      `existing/2` the start itself reads. Empty from the start on.
  """

  use Ash.Resource,
    domain: AshTemplate.Points,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query
  alias AshTemplate.Points.Seasons
  alias RegentPoints.{Entry, Rules}

  actions do
    action :mine, :map do
      description "Reads the account's Points, its seasons and, before the start, what the start adds."
      run fn _input, %{actor: actor} -> mine(actor) end
    end
  end

  policies do
    policy action(:mine) do
      authorize_if actor_attribute_equals(:role, :human)
      authorize_if {RegentAgents.Checks.Paired, repo: AshTemplate.Repo}
    end
  end

  defp mine(actor) do
    seasons = Seasons.at(DateTime.utc_now())
    before? = Seasons.phase(seasons) == :before

    with {:ok, summary} <- RegentPoints.summary(actor: actor),
         {:ok, seasons} <- earned(seasons, summary.period_bonuses, actor),
         {:ok, at_start} <- if(before?, do: at_start(actor.human_account_id), else: {:ok, []}) do
      {:ok, Map.merge(summary, %{seasons: seasons, at_start: at_start})}
    end
  end

  defp earned(seasons, bonuses, actor) do
    program = Rules.program()

    Enum.reduce_while(Enum.reverse(seasons), {:ok, []}, fn season, {:ok, later} ->
      case season_earned(season, program, actor) do
        {:ok, earned} ->
          bonus = Enum.find(bonuses, &(&1.program_id == program and &1.period == season.season))
          {:cont, {:ok, [Map.merge(season, %{earned_micro: earned, bonus: bonus}) | later]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp season_earned(%{state: :upcoming}, _program, _actor), do: {:ok, nil}

  defp season_earned(%{starts_at: from, ends_at: to}, program, actor) do
    id = actor.human_account_id

    Entry
    |> Ash.Query.filter(
      account_id == ^id and program_id == ^program and earned_at >= ^from and earned_at < ^to
    )
    |> Ash.Query.for_read(:read, %{}, actor: actor)
    |> Ash.sum(:points_micro_delta)
    |> case do
      # Floored at nothing, as the library counts a period's earned for its bonus.
      {:ok, sum} -> {:ok, max(sum || 0, 0)}
      {:error, _} = error -> error
    end
  end

  defp at_start(account_id) do
    Rules.start_rules()
    |> Enum.filter(&Rules.enabled?/1)
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, held} ->
      case Rules.adapter(id).held(id, account_id) do
        {:ok, true} -> {:cont, {:ok, held ++ [id]}}
        {:ok, false} -> {:cont, {:ok, held}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end

defmodule AshTemplateWeb.PointsEntries do
  @moduledoc """
  How the Points page and the agent's Points answer describe one account's
  Points (`AshTemplate.Points.my_points/1` and the board every reader shares,
  `AshTemplate.Points.Board`), so both say the same thing about each action,
  entry, season and place.
  """

  alias RegentPoints.{Amount, Rules, Seasons}

  @doc "What became of an entry: counted, cut to nothing by a daily limit, or a correction."
  def status(%{reversal_of_entry_id: id}) when not is_nil(id), do: :correction
  def status(%{points_micro_delta: 0}), do: :allowance_reached
  def status(_entry), do: :counted

  def status_label(:counted), do: "Counted"
  def status_label(:allowance_reached), do: "Limit reached"
  def status_label(:correction), do: "Correction"

  @doc "Who earned an entry, by the name the person gave their agent."
  def agent_name(%{actor_kind: "agent", actor_id: id}, names),
    do: Map.get(names, id, "Previously connected agent")

  def agent_name(_entry, _names), do: nil

  @doc """
  Every action a Points page lists (`RegentPoints.Rules.groups/0`), under the
  site it belongs to, whichever site earns it, with what the account has done of
  each and its points: `[%{title, items}]`, `title` the site's name. A one-time
  action is done once it was earned anywhere; a daily one shows today's count
  against its daily count. Before the start, a one-time action the account
  already has (`standing.at_start`) is done and marked as added at the start.
  After the last season nothing earns, so none is listed.
  """
  def todo(standing) do
    if Seasons.phase(standing.seasons) == :ended, do: [], else: groups(standing)
  end

  defp groups(standing) do
    room = daily_room(standing)

    for %{site: site, rules: rules} <- Rules.groups() do
      %{title: site, items: Enum.map(rules, &item(&1, standing, room))}
    end
  end

  @doc """
  The one limit every daily action shares, whoever acted and on whichever site:
  `%{label, used, of, value}`, or nil while no daily action earns on this site.
  """
  def daily_limit(standing) do
    case daily_room(standing) do
      nil ->
        nil

      %{limit: limit, remaining: remaining} ->
        used = whole(limit - remaining)

        %{
          label: "Daily limit",
          used: used,
          of: whole(limit),
          value: "#{used} of #{whole(limit)} today"
        }
    end
  end

  defp daily_room(standing), do: Enum.find(standing.allowances, &(&1.scope == "activity:account"))

  @doc "How many listed actions can still earn, today for a daily one; nil when none is listed."
  def left(groups) do
    case Enum.flat_map(groups, & &1.items) do
      [] -> nil
      items -> Enum.count(items, & &1.left)
    end
  end

  @doc """
  Where Points stands, in a few words: not started, its start date, the season
  running and the days left in it, or every season over.
  """
  def season_line(seasons) do
    case {Seasons.phase(seasons), Enum.find(seasons, &(&1.state == :running))} do
      {:running, %{season: season, days_left: days}} ->
        "Season #{season} of #{length(seasons)} · #{days} #{if days == 1, do: "day", else: "days"} left"

      {:ended, nil} ->
        "The last season has ended."

      {:before, nil} ->
        case hd(seasons).starts_at do
          nil -> "Points hasn’t started."
          starts_at -> "Points starts #{Calendar.strftime(starts_at, "%-d %b %Y")}."
        end
    end
  end

  @doc """
  The shared board for one reader: `%{rows, you, rank}`. `reader` is the reader's
  account id and `standing` their own Points (`AshTemplate.Points.my_points/1`), or
  `nil` while it is not read. `you` is the reader's row when they sit below the
  listed rows, with the place and total from their summary; `rank` is their place
  wherever they sit. The rows' account ids stay here: none reaches a page or an
  agent. A row's `name` is `nil` when the person shows by their `wallet`, under its
  `ens_name` when it has one. A row's `line` is its position in the list: names and
  places repeat, lines do not.
  """
  def board(%{top: top}, reader, standing) do
    own = Enum.find(top, &(&1.account_id == reader))
    you = below(own, standing)

    %{
      rows:
        top
        |> Enum.with_index(1)
        |> Enum.map(fn {row, line} ->
          %{
            line: line,
            rank: row.rank,
            name: row.name,
            wallet: row.wallet,
            ens_name: row.ens_name,
            squares: row.squares,
            picture: row.picture,
            points: Amount.format(row.points_micro),
            you: row.account_id == reader
          }
        end),
      you: you,
      rank: if(own, do: own.rank, else: you && you.rank)
    }
  end

  # The reader's own row under the listed ones, while they have a place.
  defp below(nil, %{place: place, balance_micro: total}) when is_integer(place),
    do: %{rank: place, points: Amount.format(total)}

  defp below(_own, _standing), do: nil

  @doc "The agent's Points answer: the same figures the Points page shows."
  def answer(standing, board, reader) do
    board = board(board, reader, standing)

    %{
      points: Amount.format(standing.balance_micro),
      earned_today: Amount.format(standing.earned_today_micro),
      earned_yesterday: Amount.format(standing.earned_yesterday_micro),
      rank: board.rank,
      activity_being_verified: standing.pending,
      to_do:
        for group <- todo(standing) do
          %{
            site: group.title,
            actions:
              for item <- group.items do
                %{
                  label: item.label,
                  repeats: item.repeats,
                  points: item.points,
                  done: item.done,
                  left: item.left,
                  at_start: item.id in standing.at_start,
                  today: item[:count]
                }
              end
          }
        end,
      daily_limits:
        Enum.map(
          standing.allowances,
          &%{
            name: limit_name(&1.scope),
            limit: Amount.format(&1.limit),
            remaining: Amount.format(&1.remaining)
          }
        ),
      leaderboard:
        Enum.map(board.rows, &Map.take(&1, [:rank, :name, :wallet, :ens_name, :points, :you])),
      entries:
        Enum.map(standing.entries, fn entry ->
          %{
            label: Rules.label(entry.rule_id),
            points: Amount.format(entry.points_micro_delta),
            status: status(entry),
            allowance_reduction: Amount.format(entry.cap_reduction_micro),
            by: if(entry.actor_kind == "agent", do: "agent", else: "person"),
            agent: agent_name(entry, standing.agent_names),
            earned_at: entry.earned_at
          }
        end),
      seasons:
        Enum.map(standing.seasons, fn season ->
          %{
            season: season.season,
            starts_at: season.starts_at,
            ends_at: season.ends_at,
            state: season.state,
            days_left: season.days_left,
            earned: season.earned_micro && Amount.format(season.earned_micro),
            bonus:
              season.bonus &&
                %{
                  points: Amount.format(season.bonus.bonus_micro),
                  nft_count: season.bonus.nft_count,
                  bonus_percent: season.bonus.bonus_percent
                }
          }
        end),
      more: standing.more?
    }
  end

  defp limit_name("activity:account"), do: "Daily actions, you and your agents"

  defp item(%{"id" => id, "category" => "milestone", "points" => points}, standing, _room) do
    at_start? = id in standing.at_start
    %{times: times} = Map.fetch!(standing.done, id)
    done = at_start? or times >= 1

    %{
      id: id,
      label: Rules.label(id),
      repeats: "once",
      points: to_string(points),
      done: done,
      left: not done
    }
    |> then(&if at_start?, do: Map.put(&1, :note, "Added at the start"), else: &1)
  end

  # A daily action stays to do until today's count is used, unless the daily limit
  # this site reads is spent.
  defp item(
         %{"id" => id, "category" => "activity", "points" => points, "count" => of},
         standing,
         room
       )
       when is_integer(of) do
    %{times: times} = Map.fetch!(standing.done, id)

    %{
      id: id,
      label: Rules.label(id),
      repeats: "daily",
      points: to_string(points),
      note: "#{times} of #{of} today",
      done: times >= of,
      left: times < of and not match?(%{remaining: 0}, room)
    }
    |> then(&if of > 1, do: Map.put(&1, :count, %{done: times, of: of}), else: &1)
  end

  defp whole(micro), do: div(micro, Rules.unit())
end

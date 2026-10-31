defmodule AshTemplateWeb.VisitLog.Cohorts do
  @moduledoc """
  Weekly sign-in cohorts, read from exported visit lines (`mix visit_log.cohorts`):
  for each week and source, the accounts that first signed in, how many reached
  the site's value action, how many came back a day and a week later, and the
  median number of value steps of an account that did. It only reads the lines it
  is given, one JSON object each, and keeps nothing.

  A line may be the site's own (`metadata` holds `visit`, `actor` and `event`), the
  same fields at the top level, or a Fly log line whose `message` is the site's
  line. Anything else is skipped.

  - **Cohort:** an account's first `signed_in` step in the export, by its week
    (from Monday, UTC). The step's own actor is the browser's from before the
    exchange, so the account is the first `person:` actor on a line of the same
    visit at or after it (docs/logging-replay-plan.md, "First touch"). A sign-in
    no later line names is counted apart.
  - **Source:** the `arrival` of the visit the account first signed in on, or
    `unknown` when that visit has none.
  - **Activated:** at least one value step (`AshTemplateWeb.VisitLog.values/0`)
    for the account at or after its first sign-in.
  - **D1, D7:** any line from the account 24 to 48 hours, or 7 to 8 days, after its
    first sign-in, as returned out of covered: an account counts only once the
    export runs past the end of its window.
  - **Median value:** the median number of value steps of an activated account.

  Times are kept to the minute.
  """

  alias AshTemplate.TextTable
  alias AshTemplateWeb.VisitLog

  @headers ["Week", "Source", "Accounts", "Activated", "D1", "D7", "Median value"]
  # A day in minutes.
  @day 24 * 60
  @empty %{
    lines: 0,
    first: nil,
    last: nil,
    arrivals: %{},
    sign_ins: [],
    people: %{},
    seen: %{},
    values: %{}
  }

  @doc "The report on `lines`, an enumerable of exported lines, as plain text."
  def report(lines), do: lines |> Enum.reduce(@empty, &take/2) |> render()

  @doc """
  One exported line as `{:ok, line}`, `line` holding its `minute` (Unix time in
  minutes), `visit`, `actor`, `name`, `where` and `outcome`, or `:skip`.
  """
  def parse(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, %{} = object} -> line(object)
      _not_an_object -> :skip
    end
  end

  defp line(%{"metadata" => %{"event" => %{} = event} = fields} = object),
    do: line(object, fields, event)

  defp line(%{"event" => %{"name" => _} = event} = object), do: line(object, object, event)
  defp line(%{"message" => "{" <> _ = inner}), do: parse(inner)
  defp line(_other), do: :skip

  defp line(object, fields, event) do
    with time when is_binary(time) <- object["time"] || object["timestamp"],
         {:ok, at, _offset} <- DateTime.from_iso8601(time) do
      {:ok,
       %{
         minute: div(DateTime.to_unix(at), 60),
         visit: text(fields["visit"]),
         actor: text(fields["actor"]),
         name: text(event["name"]),
         where: text(event["where"]),
         outcome: text(event["outcome"])
       }}
    else
      _no_time -> :skip
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_other), do: nil

  defp take(text, state) do
    case parse(text) do
      {:ok, line} -> add(state, line)
      :skip -> state
    end
  end

  defp add(state, %{minute: minute} = line) do
    %{
      state
      | lines: state.lines + 1,
        first: min(state.first || minute, minute),
        last: max(state.last || minute, minute)
    }
    |> arrival(line)
    |> sign_in(line)
    |> person(line)
    |> value(line)
  end

  # A visit's first arrival names where it came from.
  defp arrival(state, %{name: "arrival", visit: visit, minute: minute, outcome: source})
       when is_binary(visit) do
    came = {minute, source || "unknown"}
    %{state | arrivals: Map.update(state.arrivals, visit, came, &min(&1, came))}
  end

  defp arrival(state, _line), do: state

  defp sign_in(state, %{name: "step", where: "signed_in", visit: visit, minute: minute})
       when is_binary(visit),
       do: %{state | sign_ins: [{visit, minute} | state.sign_ins]}

  defp sign_in(state, _line), do: state

  # Each person's minutes, for D1 and D7, and the span each visit saw them in,
  # for naming the account a visit signed in to.
  defp person(state, %{actor: "person:" <> _ = code, visit: visit, minute: minute}) do
    seen = Map.update(state.seen, code, MapSet.new([minute]), &MapSet.put(&1, minute))
    %{state | seen: seen, people: visited(state.people, visit, code, minute)}
  end

  defp person(state, _line), do: state

  defp visited(people, nil, _code, _minute), do: people

  defp visited(people, visit, code, minute),
    do: Map.update(people, {visit, code}, {minute, minute}, &span(&1, minute))

  defp span({low, high}, minute), do: {min(low, minute), max(high, minute)}

  defp value(state, %{name: "step", where: where, actor: "person:" <> _ = code} = line) do
    if where in VisitLog.values(),
      do: %{state | values: Map.update(state.values, code, [line.minute], &[line.minute | &1])},
      else: state
  end

  defp value(state, _line), do: state

  defp render(%{lines: 0}), do: "No visit lines were read."

  defp render(state) do
    {named, unnamed} = state |> sign_ins() |> Enum.split_with(&match?({_code, _first}, &1))
    accounts = named |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Map.new(&first/1)

    table =
      accounts
      |> Enum.group_by(fn {_code, {minute, _source}} -> week(minute) end)
      |> Enum.sort_by(&elem(&1, 0), Date)
      |> Enum.flat_map(fn {week, cohort} -> week_rows(week, cohort, state) end)

    Enum.join([heading(state, length(unnamed)), TextTable.render(@headers, table)], "\n\n")
  end

  defp first({code, sign_ins}), do: {code, Enum.min(sign_ins)}

  # Each sign-in as `{code, {minute, source}}`, or `:unnamed` when no later line of
  # its visit names a person. The account is the person seen soonest at or after
  # the sign-in.
  defp sign_ins(state) do
    people =
      Enum.group_by(
        state.people,
        fn {{visit, _code}, _span} -> visit end,
        fn {{_visit, code}, span} -> {code, span} end
      )

    for {visit, minute} <- state.sign_ins do
      people
      |> Map.get(visit, [])
      |> Enum.filter(fn {_code, {_low, high}} -> high >= minute end)
      |> Enum.min_by(fn {_code, {low, _high}} -> max(low, minute) end, &<=/2, fn -> nil end)
      |> case do
        {code, _span} -> {code, {minute, source(state, visit)}}
        nil -> :unnamed
      end
    end
  end

  defp source(state, visit) do
    case state.arrivals[visit] do
      {_minute, source} -> source
      nil -> "unknown"
    end
  end

  defp week_rows(week, cohort, state) do
    sources =
      cohort
      |> Enum.group_by(fn {_code, {_minute, source}} -> source end)
      |> Enum.sort()
      |> Enum.map(fn {source, members} -> row(week, source, members, state) end)

    if match?([_, _ | _], sources),
      do: sources ++ [row(week, "all", cohort, state)],
      else: sources
  end

  defp row(week, source, members, state) do
    activated =
      members
      |> Enum.map(fn {code, {start, _source}} -> values_since(state, code, start) end)
      |> Enum.filter(&(&1 > 0))

    [
      Date.to_iso8601(week),
      source,
      length(members),
      length(activated),
      returned(members, state, @day, 2 * @day),
      returned(members, state, 7 * @day, 8 * @day),
      median(activated)
    ]
  end

  defp values_since(state, code, start),
    do: state.values |> Map.get(code, []) |> Enum.count(&(&1 >= start))

  # Of the accounts whose window the export runs past, those with any line in it.
  defp returned(members, state, from, to) do
    covered = Enum.filter(members, fn {_code, {start, _source}} -> start + to <= state.last end)

    back =
      Enum.count(covered, fn {code, {start, _source}} ->
        seen?(state, code, start + from, start + to)
      end)

    "#{back}/#{length(covered)}"
  end

  defp seen?(state, code, from, to),
    do: state.seen |> Map.get(code, MapSet.new()) |> Enum.any?(&(&1 >= from and &1 < to))

  defp median([]), do: "-"

  defp median(counts) do
    sorted = Enum.sort(counts)
    size = length(sorted)

    case Enum.slice(sorted, div(size - 1, 2), 2 - rem(size, 2)) do
      [middle] -> middle
      [low, high] -> (low + high) / 2
    end
  end

  defp week(minute),
    do: (minute * 60) |> DateTime.from_unix!() |> DateTime.to_date() |> Date.beginning_of_week()

  defp stamp(minute), do: (minute * 60) |> DateTime.from_unix!() |> DateTime.to_iso8601()

  defp heading(state, unnamed) do
    """
    Visit-log cohorts, #{stamp(state.first)} to #{stamp(state.last)}, from #{state.lines} lines.

    The window is only what this export holds. Sentinel keeps visit lines for 30 days,
    so a week's accounts are those whose first sign-in in this export fell in it; an
    account that signed in before the export began counts in the week it signed in
    again. A source is the arrival of the visit the account first signed in on.
    Activated means at least one value step (#{Enum.join(VisitLog.values(), ", ")}).
    D1 and D7 are returned/covered: any line 24 to 48 hours, or 7 to 8 days, after
    the first sign-in, out of the accounts whose window the export runs past.
    Sign-ins left out because no later line of their visit names an account: #{unnamed}.\
    """
  end
end

defmodule AshTemplateWeb.VisitLog.Cohorts do
  @moduledoc """
  Weekly sign-in cohorts, read from exported visit lines (`mix visit_log.cohorts`):
  for each week and source, the accounts that first signed in, how many reached
  the site's value action, how many came back a day and a week later, and the
  median number of value steps of an account that did. It only reads the lines it
  is given, one JSON object each, and keeps nothing.

  A line may be the site's own (`metadata` holds `visit`, `actor` and `event`), a
  Fly log line whose `message` is the site's line, or the same fields at the top
  level, the shape Sentinel's export is expected to take (not built yet).
  Anything else is skipped.

  - **Cohort:** an account's first `signed_in` step in the export, by its week
    (from Monday, UTC). The step's own actor is the browser's from before the
    exchange, so the account is the `person:` code with the earliest line of the
    same visit strictly after it, preferring a code the visit had not shown
    before the sign-in, then the earliest code by name, so ties always fall the
    same way (docs/logging-replay-plan.md, "First touch"). A sign-in no later
    line names is counted apart. Lines written before the 31 October 2026 release
    also wrote `signed_in` for a refresh of the same account.
  - **Source:** the `arrival` of the visit the account first signed in on, or
    `unknown` when that visit has none.
  - **Activated:** at least one value step (`AshTemplateWeb.VisitLog.values/0`)
    for the account at or after its first sign-in.
  - **D1, D7:** a line from the account 24 to 48 hours, or 7 to 8 days, after its
    first sign-in, as returned out of covered: an account counts only once the
    export runs past the end of its window. Only lines that carry a visit count
    as a return, and never a value step its agent did (outcome `agent`), so a
    Global Privacy Control browser, a call from outside a page and the account's
    agent at work do not make the person a returning one.
  - **Median value:** the median number of value steps of an activated account.

  Times are kept to the millisecond.
  """

  alias AshTemplate.TextTable
  alias AshTemplateWeb.VisitLog

  @headers ["Week", "Source", "Accounts", "Activated", "D1", "D7", "Median value"]
  # A day in milliseconds.
  @day 24 * 60 * 60 * 1000
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
  One exported line as `{:ok, line}`, `line` holding its `at` (Unix time in
  milliseconds), `visit`, `actor`, `name`, `where` and `outcome`, or `:skip`.
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
         at: DateTime.to_unix(at, :millisecond),
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

  defp add(state, %{at: at} = line) do
    %{
      state
      | lines: state.lines + 1,
        first: min(state.first || at, at),
        last: max(state.last || at, at)
    }
    |> arrival(line)
    |> sign_in(line)
    |> person(line)
    |> value(line)
  end

  # A visit's first arrival names where it came from.
  defp arrival(state, %{name: "arrival", visit: visit, at: at, outcome: source})
       when is_binary(visit) do
    came = {at, source || "unknown"}
    %{state | arrivals: Map.update(state.arrivals, visit, came, &min(&1, came))}
  end

  defp arrival(state, _line), do: state

  defp sign_in(state, %{name: "step", where: "signed_in", visit: visit, at: at})
       when is_binary(visit),
       do: %{state | sign_ins: [{visit, at} | state.sign_ins]}

  defp sign_in(state, _line), do: state

  # A person's lines in a visit: each time, for naming the account a visit signed
  # in to, and, for D1 and D7, each time that counts as the person coming back.
  defp person(state, %{actor: "person:" <> _ = code, visit: visit, at: at} = line)
       when is_binary(visit) do
    people = Map.update(state.people, {visit, code}, [at], &[at | &1])
    seen = if agent?(line), do: state.seen, else: Map.update(state.seen, code, [at], &[at | &1])
    %{state | people: people, seen: seen}
  end

  defp person(state, _line), do: state

  defp agent?(%{name: "step", outcome: "agent"}), do: true
  defp agent?(_line), do: false

  defp value(state, %{name: "step", where: where, actor: "person:" <> _ = code} = line) do
    if where in VisitLog.values(),
      do: %{state | values: Map.update(state.values, code, [line.at], &[line.at | &1])},
      else: state
  end

  defp value(state, _line), do: state

  defp render(%{lines: 0}), do: "No visit lines were read."

  defp render(state) do
    {named, unnamed} = state |> sign_ins() |> Enum.split_with(&match?({_code, _first}, &1))
    accounts = named |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Map.new(&first/1)

    table =
      accounts
      |> Enum.group_by(fn {_code, {at, _source}} -> week(at) end)
      |> Enum.sort_by(&elem(&1, 0), Date)
      |> Enum.flat_map(fn {week, cohort} -> week_rows(week, cohort, state) end)

    Enum.join([heading(state, length(unnamed)), TextTable.render(@headers, table)], "\n\n")
  end

  defp first({code, sign_ins}), do: {code, Enum.min(sign_ins)}

  # Each sign-in as `{code, {at, source}}`, or `:unnamed` when no line of its visit
  # strictly after it names a person.
  defp sign_ins(state) do
    people =
      Enum.group_by(
        state.people,
        fn {{visit, _code}, _times} -> visit end,
        fn {{_visit, code}, times} -> {code, times} end
      )

    for {visit, at} <- state.sign_ins do
      people
      |> Map.get(visit, [])
      |> Enum.flat_map(&candidate(&1, at))
      |> Enum.min(fn -> nil end)
      |> case do
        {_seen_before, _first_after, code} -> {code, {at, source(state, visit)}}
        nil -> :unnamed
      end
    end
  end

  # A person with a line after the sign-in at `at`, as `{seen before, first line
  # after, code}`, so the smallest is a code new to the visit before one it had
  # already shown, then the soonest, then the first by name.
  defp candidate({code, times}, at) do
    case Enum.filter(times, &(&1 > at)) do
      [] -> []
      after_it -> [{Enum.any?(times, &(&1 <= at)), Enum.min(after_it), code}]
    end
  end

  defp source(state, visit) do
    case state.arrivals[visit] do
      {_at, source} -> source
      nil -> "unknown"
    end
  end

  defp week_rows(week, cohort, state) do
    sources =
      cohort
      |> Enum.group_by(fn {_code, {_at, source}} -> source end)
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
    do: state.seen |> Map.get(code, []) |> Enum.any?(&(&1 >= from and &1 < to))

  defp median([]), do: "-"

  defp median(counts) do
    sorted = Enum.sort(counts)
    size = length(sorted)

    case Enum.slice(sorted, div(size - 1, 2), 2 - rem(size, 2)) do
      [middle] -> middle
      [low, high] -> (low + high) / 2
    end
  end

  defp week(at),
    do: at |> DateTime.from_unix!(:millisecond) |> DateTime.to_date() |> Date.beginning_of_week()

  defp stamp(at), do: at |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601()

  defp heading(state, unnamed) do
    """
    Visit-log cohorts, #{stamp(state.first)} to #{stamp(state.last)}, from #{state.lines} lines.

    The window is only what this export holds. Fly's log buffer holds hours and
    Sentinel's planned export one day; a 30-day export is still to be built. A
    week's accounts are those whose first sign-in in this export fell in it, so an
    account that signed in before the export began counts in the week it signed in
    again. Lines written before the 31 October 2026 release also counted a refresh
    of the same account as signed_in. A source is the arrival of the visit the
    account first signed in on. Activated means at least one value step
    (#{Enum.join(VisitLog.values(), ", ")}). D1 and D7 are returned/covered: a line
    24 to 48 hours, or 7 to 8 days, after the first sign-in, out of the accounts
    whose window the export runs past; only lines with a visit count, and never a
    value step the account's agent did.
    Sign-ins left out because no later line of their visit names an account: #{unnamed}.\
    """
  end
end

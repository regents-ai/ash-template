defmodule AshTemplate.ProductEvents.Cohorts do
  @moduledoc """
  Weekly account cohorts from the product events (`AshTemplate.ProductEvents`),
  as a plain text table, for `mix product_events.cohorts` and
  `AshTemplate.Release.product_cohorts/0`. It only reads.

  An account joins the week of its `account_created` event, under the source its
  browser first came from. For each week, and each source in it:

    * accounts: how many joined;
    * activated: how many have reached the site's value at least once
      (`value_reached`);
    * D1 and D7: how many have any event 24 to 48 hours, and 7 to 8 days, after
      joining;
    * median value: the median count of `value_reached` events per activated
      account.

  Accounts that signed in before product events began join the week of their
  first sign-in after it.
  """

  alias AshTemplate.TextTable

  @headers ["Week", "Source", "Accounts", "Activated", "D1", "D7", "Median value"]
  @notes """
  Weeks start on Monday, in UTC. "all" is every source of the week together.
  A week that ended less than eight days ago has not reached D7 for all its accounts.\
  """

  @doc "The report for the database `repo` reaches."
  # The statement names only the repository's own configured schema, never input.
  # sobelow_skip ["SQL.Query"]
  def report(repo) do
    case Ecto.Adapters.SQL.query!(repo, sql(repo.default_prefix()), []) do
      %{rows: []} -> "No account has been created since product events began."
      %{rows: rows} -> TextTable.render(@headers, Enum.map(rows, &row/1)) <> "\n\n" <> @notes
    end
  end

  defp row([week, source, accounts, activated, d1, d7, median]) do
    [
      Date.to_iso8601(week),
      source,
      accounts,
      share(activated, accounts),
      share(d1, accounts),
      share(d7, accounts),
      median(median)
    ]
  end

  defp share(count, total), do: "#{count} (#{round(count * 100 / total)}%)"

  defp median(nil), do: "-"
  defp median(median), do: :erlang.float_to_binary(median / 1, decimals: 1)

  # Each account's events are read once, through its own index.
  defp sql(schema) do
    events = ~s("#{schema}".product_events)

    """
    WITH cohort AS (
      SELECT human_account_id, inserted_at AS joined_at, coalesce(source, 'unknown') AS source
      FROM #{events}
      WHERE name = 'account_created'
    ),
    joined AS (
      SELECT date_trunc('week', c.joined_at)::date AS week,
             c.source,
             count(*) FILTER (WHERE e.name = 'value_reached') AS value_events,
             bool_or(e.inserted_at >= c.joined_at + interval '1 day'
                     AND e.inserted_at < c.joined_at + interval '2 days') AS d1,
             bool_or(e.inserted_at >= c.joined_at + interval '7 days'
                     AND e.inserted_at < c.joined_at + interval '8 days') AS d7
      FROM cohort AS c
      JOIN #{events} AS e ON e.human_account_id = c.human_account_id
      GROUP BY c.human_account_id, c.joined_at, c.source
    )
    SELECT week,
           CASE WHEN grouping(source) = 1 THEN 'all' ELSE source END,
           count(*),
           count(*) FILTER (WHERE value_events > 0),
           count(*) FILTER (WHERE d1),
           count(*) FILTER (WHERE d7),
           percentile_cont(0.5) WITHIN GROUP (ORDER BY value_events)
             FILTER (WHERE value_events > 0)
    FROM joined
    GROUP BY GROUPING SETS ((week), (week, source))
    ORDER BY week DESC, grouping(source) DESC, source
    """
  end
end

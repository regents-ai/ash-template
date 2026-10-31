defmodule AshTemplate.TopQueries do
  @moduledoc """
  The statements on this site's own schema that took the most database time, from
  PostgreSQL's `pg_stat_statements`, as a plain text table, for
  `mix db.top_queries` and `AshTemplate.Release.top_queries/1`. It only reads:
  when the extension is not there it says so and stops, and it never creates it.

  Every database on the server shares one set of statistics, so only this
  database's statements that name a table in the repository's schema, written
  `"schema".` or `schema.`, are shown; a statement that only mentions the name in
  passing, or names a schema that merely starts or ends with it, is not.
  PostgreSQL hides the text of another login's statements, so a login sees its own
  unless it may read all statistics.
  """

  alias AshTemplate.TextTable

  @extension """
  SELECT n.nspname
  FROM pg_catalog.pg_extension AS e
  JOIN pg_catalog.pg_namespace AS n ON n.oid = e.extnamespace
  WHERE e.extname = 'pg_stat_statements'
  """
  @headers ["Rank", "Calls", "Total ms", "Mean ms", "Rows", "Statement"]

  @doc "The report: the `limit` statements that took the most time in all, most first."
  def report(repo, limit) when is_integer(limit) and limit > 0 do
    case Ecto.Adapters.SQL.query!(repo, @extension, []) do
      %{rows: []} -> "pg_stat_statements is not enabled on this database."
      %{rows: [[schema]]} -> statements(repo, schema, limit)
    end
  end

  @doc "The count an operator gave, a whole number from 1 to 100."
  def limit!(given) do
    case Integer.parse(given) do
      {limit, ""} when limit in 1..100 -> limit
      _other -> raise ArgumentError, "the count must be a whole number from 1 to 100"
    end
  end

  # The extension's schema comes from the catalog and the site's from the
  # repository's configuration; both are quoted as identifiers, and the site's
  # also reaches the statement only as parameters, so no part of it is input.
  # sobelow_skip ["SQL.Query"]
  defp statements(repo, schema, limit) do
    prefix = repo.default_prefix()

    sql = """
    SELECT s.calls, s.total_exec_time, s.mean_exec_time, s.rows, s.query
    FROM #{identifier(schema)}.pg_stat_statements AS s
    JOIN pg_catalog.pg_database AS d ON d.oid = s.dbid
    WHERE d.datname = current_database()
      AND (strpos(s.query, $1) > 0 OR s.query ~ $2)
    ORDER BY s.total_exec_time DESC
    LIMIT $3
    """

    case Ecto.Adapters.SQL.query(repo, sql, [quoted(prefix), bare(prefix), limit]) do
      {:ok, %{rows: []}} ->
        "No statement on #{identifier(prefix)} has been recorded yet."

      {:ok, %{rows: rows}} ->
        TextTable.render(@headers, rows |> Enum.with_index(1) |> Enum.map(&row/1))

      {:error, error} ->
        "pg_stat_statements could not be read: #{Exception.message(error)}"
    end
  end

  # A name as PostgreSQL quotes an identifier: in double quotes, each one inside doubled.
  defp identifier(name), do: ~s(") <> String.replace(name, ~s("), ~s("")) <> ~s(")

  # A table in the schema as Ecto and Ash write it: `"ash_template_app".`.
  defp quoted(prefix), do: identifier(prefix) <> "."

  # The same written bare, as a pattern: the name at the start of a word, then a
  # dot, so `ash_template_app.` matches and `old_ash_template_app.` does not.
  defp bare(prefix), do: "\\m" <> Regex.escape(prefix) <> "\\."

  defp row({[calls, total, mean, rows, query], rank}),
    do: [rank, calls, round(total), Float.round(mean / 1, 2), rows, statement(query)]

  # One line each, cut short.
  defp statement(query), do: query |> String.split() |> Enum.join(" ") |> String.slice(0, 160)
end

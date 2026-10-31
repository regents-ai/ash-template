defmodule AshTemplate.TextTable do
  @moduledoc "A plain text table for operator reports: a row a line, each column padded to fit."

  @doc "The table, headers first; every cell is written with `to_string/1`."
  def render(headers, rows) do
    lines = Enum.map([headers | rows], fn row -> Enum.map(row, &to_string/1) end)
    widths = Enum.zip_with(lines, &width/1)

    Enum.map_join(lines, "\n", fn line ->
      line
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {cell, size} -> String.pad_trailing(cell, size) end)
      |> String.trim_trailing()
    end)
  end

  defp width(column), do: column |> Enum.map(&String.length/1) |> Enum.max()
end

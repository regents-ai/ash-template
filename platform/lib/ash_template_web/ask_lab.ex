defmodule AshTemplateWeb.AskLab do
  @moduledoc """
  The ask bar's answers for the lab page `/animations/ask` (`AshTemplateWeb.AskLabLive`).

  A question becomes a plan: a title and one to three blocks, each chosen from a
  closed list (`blocks/0`) and filled from the sample data below. The matching is a
  plain keyword match on the question's words and its first number; there is no
  model, no network and nothing stored. `check/1` holds every plan to the list's
  contract before the page draws any of it, so a block the list does not know, or
  one missing what it needs, never reaches the page.
  """

  @blocks [:figure, :list, :chart, :activity, :confirm]

  @examples ["Points this week", "Offers under 50 USDC", "Archive old notes"]

  @offers [
    %{name: "Weekly summary", price: 25},
    %{name: "Code review", price: 35},
    %{name: "Logo design", price: 40},
    %{name: "Data cleanup", price: 60},
    %{name: "Landing page", price: 120}
  ]

  # How many days ago each sample note was last opened.
  @note_ages [4, 12, 41, 52, 88]

  @kinds [:read, :think, :tool, :write, :waiting_for_you, :done, :failed]

  @type block :: %{block: atom(), props: map()}
  @type plan :: %{title: String.t(), blocks: [block()]}

  @doc "The blocks a plan may be made of, and nothing else."
  def blocks, do: @blocks

  @doc "Three questions the bar answers, shown when it is empty or finds no match."
  def examples, do: @examples

  @doc """
  The plan for a question, or `:no_match` when none of its words is one the bar
  knows. `now` places the sample agent's steps and the chart's points.
  """
  @spec answer(String.t(), DateTime.t()) :: {:ok, plan()} | :no_match
  def answer(question, now) do
    words = question |> String.downcase() |> String.split(~r/[^a-z0-9.,]+/, trim: true)
    number = Enum.find_value(words, &number/1)

    cond do
      Enum.any?(words, &(&1 in ~w(archive note notes))) ->
        {:ok, archive(number || 30)}

      Enum.any?(words, &(&1 in ~w(offer offers))) ->
        {:ok, offers(number)}

      Enum.any?(words, &(&1 in ~w(point points))) ->
        {:ok, points(now)}

      Enum.any?(words, &(&1 in ~w(agent agents activity doing working pira))) ->
        {:ok, agents(now)}

      Enum.any?(words, &(&1 in ~w(price regent))) ->
        {:ok, price(now)}

      true ->
        :no_match
    end
  end

  @doc """
  Holds a plan to the block list: a title, one to three blocks, each one of
  `blocks/0` with every property its kind needs. The page draws only a plan that
  passes.
  """
  @spec check(term()) :: {:ok, plan()} | {:error, String.t()}
  def check(%{title: title, blocks: blocks} = plan) when is_binary(title) do
    case one_to_three?(blocks) && Enum.reject(blocks, &block?/1) do
      false -> {:error, "a plan is a title and one to three blocks"}
      [] -> {:ok, plan}
      [bad | _] -> {:error, "unknown or incomplete block #{inspect(bad[:block])}"}
    end
  end

  def check(_plan), do: {:error, "a plan is a title and one to three blocks"}

  defp one_to_three?([_]), do: true
  defp one_to_three?([_, _]), do: true
  defp one_to_three?([_, _, _]), do: true
  defp one_to_three?(_blocks), do: false

  defp block?(%{block: :figure, props: %{label: l, value: v, unit: u, line: line}}),
    do: text?([l, v, line]) and (is_nil(u) or is_binary(u))

  defp block?(%{block: :list, props: %{label: l, rows: rows, none: none}}),
    do: text?([l, none]) and is_list(rows) and Enum.all?(rows, &row?/1)

  defp block?(%{block: :chart, props: %{label: l, points: [_ | _] = points}}),
    do: text?([l]) and Enum.all?(points, &point?/1)

  defp block?(%{block: :activity, props: %{label: l, steps: [_ | _] = steps}}),
    do: text?([l]) and Enum.all?(steps, &(&1[:kind] in @kinds and is_binary(&1[:label])))

  defp block?(%{block: :confirm, props: %{label: l, rows: [_ | _] = rows, action: a}}),
    do: text?([l, a]) and Enum.all?(rows, &row?/1)

  defp block?(_block), do: false

  defp text?(values), do: Enum.all?(values, &(is_binary(&1) and &1 != ""))
  defp row?(row), do: text?([row[:name], row[:value]])

  defp point?(%{at: %DateTime{}, value: value, figure: f, time: t}) when is_number(value),
    do: text?([f, t])

  defp point?(_point), do: false

  # The plans, from the sample data.

  defp archive(days) do
    count = @note_ages |> Enum.count(&(&1 > days)) |> Integer.to_string()

    %{
      title: "Archive",
      blocks: [
        figure("Notes", count, nil, "Older than #{grouped(days)} days"),
        %{
          block: :confirm,
          props: %{
            label: "Archive",
            rows: [
              %{name: "Notes", value: count},
              %{name: "Older than", value: "#{grouped(days)} days"}
            ],
            action: "Archive"
          }
        }
      ]
    }
  end

  defp offers(limit) do
    shown = Enum.filter(@offers, &(is_nil(limit) or &1.price <= limit))
    label = if limit, do: "Under #{grouped(limit)} USDC", else: "Offers"

    %{
      title: "Offers",
      blocks: [
        figure("Offers", Integer.to_string(length(shown)), nil, label),
        %{
          block: :list,
          props: %{
            label: label,
            rows: Enum.map(shown, &%{name: &1.name, value: "#{&1.price}.00 USDC"}),
            none: "No offers"
          }
        }
      ]
    }
  end

  defp points(now) do
    %{
      title: "Points",
      blocks: [
        figure("Points", "1,240", nil, "This week"),
        chart("Points earned", [120, 180, 90, 210, 160, 140, 60], now)
      ]
    }
  end

  defp agents(now) do
    %{
      title: "Agents",
      blocks: [
        %{block: :activity, props: %{label: "Pira's activity", steps: steps(now)}},
        %{
          block: :list,
          props: %{
            label: "Agents",
            rows: [
              %{name: "Pira", value: "Running"},
              %{name: "Juno", value: "Idle"},
              %{name: "Moss", value: "Idle"}
            ],
            none: "No agents"
          }
        }
      ]
    }
  end

  defp price(now) do
    %{
      title: "Price",
      blocks: [
        figure("$REGENT", "0.0412", "USDC", "This week"),
        chart("Price (USDC)", [0.0371, 0.0384, 0.0379, 0.0398, 0.0405, 0.0401, 0.0412], now)
      ]
    }
  end

  defp figure(label, value, unit, line),
    do: %{block: :figure, props: %{label: label, value: value, unit: unit, line: line}}

  # One point a day, the last today.
  defp chart(label, values, now) do
    points =
      values
      |> Enum.with_index(1 - length(values))
      |> Enum.map(fn {value, back} ->
        at = now |> DateTime.add(back * 86_400) |> DateTime.truncate(:second)
        %{at: at, value: value, figure: figure_text(value), time: Calendar.strftime(at, "%-d %b")}
      end)

    %{block: :chart, props: %{label: label, points: points}}
  end

  defp steps(now) do
    [
      step("s1", :read, "Offers board", now, -540, -500),
      step("s2", :think, "Price check", now, -500, -420),
      step("s3", :tool, "Order list", now, -420, nil)
    ]
  end

  defp step(id, kind, label, now, from, to) do
    %{
      id: id,
      kind: kind,
      label: label,
      started_at: DateTime.add(now, from),
      finished_at: to && DateTime.add(now, to)
    }
  end

  defp number(word) do
    case Integer.parse(String.replace(word, ",", "")) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp figure_text(value) when is_integer(value), do: grouped(value)
  defp figure_text(value), do: :erlang.float_to_binary(value, decimals: 4)

  defp grouped(n) when n >= 1000,
    do:
      grouped(div(n, 1000)) <> "," <> String.pad_leading(Integer.to_string(rem(n, 1000)), 3, "0")

  defp grouped(n), do: Integer.to_string(n)
end

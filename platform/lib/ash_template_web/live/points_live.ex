defmodule AshTemplateWeb.PointsLive do
  @moduledoc """
  Private Account Points presentation: the total, the actions left with where
  Points stands, the leaderboard, the NFT bonus with each season and the bonus
  added at its end, and the activity. The pieces are `Regent.Points`; this page
  supplies their words.
  """
  use AshTemplateWeb, :html
  import AshTemplateWeb.Components.PageHead, only: [page_head: 1]
  import AshTemplateWeb.Components.Shell, only: [account_picture: 1]
  alias AshTemplateWeb.PointsEntries
  alias RegentPoints.{Amount, Rules}

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :points, AshTemplateWeb.Read, required: true

  attr :board, AshTemplateWeb.Read,
    required: true,
    doc: "the board every signed-in reader shares (AshTemplate.Points.Board)"

  attr :bonus, AshTemplateWeb.Read,
    required: true,
    doc: "the NFT tier the account's wallets hold now"

  attr :earning, :list, required: true, doc: "the catalog rules earning now"

  def page(assigns) do
    open? = assigns.earning != []
    summary = assigns.points.value
    groups = if summary, do: PointsEntries.todo(summary), else: []

    board =
      assigns.board.value &&
        PointsEntries.board(assigns.board.value, assigns.account.id, summary)

    assigns =
      assign(assigns,
        open?: open?,
        summary: summary,
        groups: Enum.map(groups, &linked/1),
        left: PointsEntries.left(groups),
        places: board,
        rows: if(summary, do: Enum.map(summary.entries, &row(&1, summary.agent_names)), else: [])
      )

    ~H"""
    <article id="points-page" class="account-page">
      <.page_head title="Points" />
      <Regent.Account.signed_out
        :if={is_nil(@account)}
        id="points-signed-out"
        reason={@signed_out_reason}
      >
        <:sign_in>
          <Regent.Primitives.button type="button" data-account-target="sign-in">
            Sign in
          </Regent.Primitives.button>
        </:sign_in>
      </Regent.Account.signed_out>
      <Regent.Points.layout :if={@account}>
        <:total>
          <Regent.Points.total
            id="points-total"
            total={@summary && Amount.format(@summary.balance_micro)}
            today={@summary && Amount.format(@summary.earned_today_micro)}
            yesterday={@summary && Amount.format(@summary.earned_yesterday_micro)}
            rank={@places && @places.rank && to_string(@places.rank)}
            pending={if @summary, do: @summary.pending, else: 0}
            state={state(@points)}
          >
            A record of everything you and your agents do across Regents. One total, on every site.
          </Regent.Points.total>
        </:total>
        <:main>
          <Regent.Points.todo :if={@summary} id="points-todo" left={@left} groups={@groups}>
            <p id="points-season" role="status">{PointsEntries.season_line(@summary.seasons)}</p>
          </Regent.Points.todo>
          <Regent.Points.activity
            :if={@summary}
            id="points-activity"
            rows={@rows}
            more={@summary.more?}
          >
            <:tip :let={row}>
              <Regent.Primitives.tip id={"points-limit-#{row.id}"} label="About this award’s limit">
                {row.note}
              </Regent.Primitives.tip>
            </:tip>
          </Regent.Points.activity>
        </:main>
        <:side>
          <Regent.Points.board
            id="points-board"
            rows={if @places, do: @places.rows, else: []}
            you={@places && @places.you}
            state={state(@board)}
          >
            <:face :let={row}>
              <.account_picture
                id={"points-board-face-#{row.line}"}
                squares={row.squares}
                picture={row.picture}
                size={28}
              />
            </:face>
          </Regent.Points.board>
          <Regent.Points.bonus
            id="points-bonus"
            state={bonus_state(@open?, @bonus)}
            nfts={@bonus.value && @bonus.value.nft_count}
            percent={@bonus.value && @bonus.value.percent}
            message={"Your NFTs could not be checked. #{retry(@bonus.error)}"}
            tiers={tiers(@bonus.value)}
            periods={if @summary, do: Enum.map(@summary.seasons, &season/1), else: []}
          >
            <:tip>
              <Regent.Primitives.tip id="points-bonus-about" label="About your points bonus">
                Points runs in {Rules.season_count()} seasons of 30 days.
                Animata I, Animata II and Regents Club count across your verified linked wallets.
                At the end of each season, the tier your wallets hold that day adds its
                bonus to the points you earned in that season, one-time awards included.
              </Regent.Primitives.tip>
            </:tip>
          </Regent.Points.bonus>
        </:side>
      </Regent.Points.layout>
    </article>
    """
  end

  # The page where each action is done, for the ones this site has a page for.
  @links %{
    "social.x" => "/account/connections",
    "social.github" => "/account/connections",
    "social.farcaster" => "/account/connections",
    "agent.activated" => "/account/agents"
  }

  defp linked(group) do
    items =
      Enum.map(group.items, fn item ->
        item
        |> Map.put(:points, "+" <> item.points)
        |> then(&if href = @links[item.id], do: Map.put(&1, :href, href), else: &1)
      end)

    %{group | items: items}
  end

  defp row(entry, agent_names) do
    status = PointsEntries.status(entry)
    %{points_micro_delta: delta, cap_reduction_micro: cut} = entry

    %{
      id: entry.id,
      label: Rules.label(entry.rule_id),
      by: PointsEntries.agent_name(entry, agent_names) || "You",
      at: Calendar.strftime(entry.earned_at, "%-d %b, %H:%M UTC"),
      points: signed(delta),
      status: if(status != :counted, do: PointsEntries.status_label(status)),
      note:
        if cut > 0 do
          "#{Amount.format(delta + cut)} before limits, #{Amount.format(delta)} awarded. " <>
            "The rest was over the daily limit."
        end
    }
  end

  defp signed(micro) when micro < 0, do: "−" <> Amount.format(-micro)
  defp signed(micro), do: "+" <> Amount.format(micro)

  # Each season in order: its dates, what was earned in it once it began, and the
  # bonus added at its end.
  defp season(%{starts_at: nil} = season),
    do: %{label: "Season #{season.season}", value: "30 days"}

  defp season(season) do
    %{
      label: "Season #{season.season}",
      value:
        Enum.join(
          [
            "#{Calendar.strftime(season.starts_at, "%-d %b")} – #{Calendar.strftime(season.ends_at, "%-d %b")}",
            season.earned_micro && "#{Amount.format(season.earned_micro)} earned",
            season.bonus &&
              "+#{Amount.format(season.bonus.bonus_micro)} (#{season.bonus.nft_count} NFTs, +#{season.bonus.bonus_percent}%)"
          ]
          |> Enum.reject(&is_nil/1),
          " · "
        )
    }
  end

  # Ascending tiers, each running up to the next one's minimum.
  defp tiers(held) do
    ascending = Enum.sort(RegentPoints.Bonus.tiers())
    next = Enum.map(Enum.drop(ascending, 1), &elem(&1, 0)) ++ [nil]
    count = held && held.nft_count

    Enum.zip_with(ascending, next, fn
      {minimum, percent}, nil ->
        %{range: "#{minimum}+", percent: percent, held: is_integer(count) and count >= minimum}

      {minimum, percent}, upper ->
        %{
          range: "#{minimum}–#{upper - 1}",
          percent: percent,
          held: is_integer(count) and count in minimum..(upper - 1)
        }
    end)
  end

  defp state(%{state: state}) when state in [:idle, :loading], do: :loading
  defp state(%{state: state}) when state in [:ready, :empty], do: :ready
  defp state(%{state: state}), do: state

  defp bonus_state(false, _bonus), do: :closed
  defp bonus_state(true, bonus), do: state(bonus)

  # Reading again at once while limited would only be refused again.
  defp retry(:limited), do: "Try again in a minute."
  defp retry(_reason), do: "Try refreshing this page."
end

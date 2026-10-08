defmodule AshTemplateWeb.PointsLive do
  @moduledoc "Private Account Points presentation; every award shows base and NFT bonus separately."
  use AshTemplateWeb, :html
  alias RegentPoints.{Amount, Rules}
  attr :account, :map, default: nil
  attr :points, AshTemplateWeb.Read, required: true

  def page(assigns) do
    ~H"""
    <article id="points-page" class="account-page">
      <header class="account-heading">
        <p class="account-kicker">Settings</p>
        <h1 tabindex="-1">Points</h1>
        <p class="account-lede">
          Eligible activity by you and your connected agents, in one account.
        </p>
      </header>
      <section :if={is_nil(@account)} class="account-panel">
        <h2>Sign in to see your points</h2>
        <Regent.Primitives.button type="button" data-account-target="sign-in">Sign in</Regent.Primitives.button>
      </section>
      <p :if={@account && is_nil(@points.value) && @points.state in [:idle, :loading]} role="status">
        Reading your points…
      </p>
      <Regent.Primitives.notice :if={@points.state == :error} tone="error">
        Points could not be read. Try refreshing this page.
      </Regent.Primitives.notice>
      <%!-- Keeps its space while unseen, so a failed refresh never moves the panels. --%>
      <Regent.Primitives.notice
        :if={@account && @points.value}
        tone="warning"
        class="points-stale"
        data-unseen={@points.state != :stale}
      >
        These are your last saved figures. The latest refresh failed.
      </Regent.Primitives.notice>
      <div :if={@account && @points.value} class="account-grid">
        <section class="account-panel account-details">
          <h2>Your points</h2>
          <dl>
            <div>
              <dt>Confirmed</dt><dd>{Amount.format(@points.value.balance_micro)}</dd>
            </div>
            <div>
              <dt>Earned today (UTC)</dt><dd>{Amount.format(@points.value.earned_today_micro)}</dd>
            </div>
            <div>
              <dt>Activity being verified</dt><dd>{@points.value.pending}</dd>
            </div>
          </dl>
          <p :if={@points.value.active_rules == []}>
            Points earning has not opened yet.
          </p>
        </section>
        <section class="account-panel account-details">
          <h2>
            Your bonus
            <Regent.Primitives.tip id="points-bonus-about" label="About your points bonus">
              Animata I, Animata II and Regents Club count across your verified linked wallets.
              <span :for={{minimum, percent} <- Enum.reverse(RegentPoints.Bonus.tiers())}>
                {minimum}+ NFTs: +{percent}%.
              </span>
              The highest tier applies once to base points awarded after limits, including
              one-time awards. Each award keeps the tier from the time of the action.
              Transfers change future bonuses, not earlier awards.
            </Regent.Primitives.tip>
          </h2>
          <p :if={is_nil(@points.value.nft_count)}>
            Ownership has not been checked for your current linked wallets.
          </p>
          <p :if={!is_nil(@points.value.nft_count)}>
            {@points.value.nft_count} NFTs · +{@points.value.bonus_percent}% on base points
          </p>
          <p :if={@points.value.nft_checked_at}>
            Last checked: {Calendar.strftime(@points.value.nft_checked_at, "%d %b %Y %H:%M UTC")}.
          </p>
        </section>
        <section :if={@points.value.active_rules != []} class="account-panel account-details">
          <h2>
            Daily base allowances
            <Regent.Primitives.tip id="points-allowances-about" label="About daily allowances">
              All your agents share one allowance. Your per-action limits are separate from theirs.
              Each action uses one pool. Allowances reset at midnight UTC.
              One-time awards do not use these allowances.
            </Regent.Primitives.tip>
          </h2>
          <dl>
            <div :for={cap <- @points.value.allowances}>
              <dt>{scope_name(cap.scope)}</dt><dd>{Amount.format(cap.remaining)} remaining</dd>
            </div>
          </dl>
        </section>
        <section class="account-panel">
          <h2>Recent points activity</h2>
          <p :if={@points.value.entries == []}>No confirmed points activity yet.</p>
          <ol>
            <li :for={entry <- @points.value.entries}>
              <p>
                {String.capitalize(entry.source_app)} · {Rules.label(entry.rule_id)} · {actor_name(
                  entry,
                  @points.value.agent_names
                )}
              </p>
              <p>
                {Amount.format(entry.base_points_micro)} awarded base + {Amount.format(
                  entry.bonus_points_micro
                )} NFT bonus ({entry.bonus_percent}%) = {Amount.format(entry.points_micro_delta)} points
              </p>
              <Regent.Primitives.tip
                :if={entry.cap_reduction_micro > 0}
                id={"points-cap-#{entry.id}"}
                label="About this award’s allowance"
              >
                {Amount.format(entry.base_points_micro + entry.cap_reduction_micro)} base before limits; {Amount.format(
                  entry.base_points_micro
                )} awarded. {Amount.format(entry.cap_reduction_micro)} exceeded the daily or per-action allowance.
              </Regent.Primitives.tip>
              <p>
                {entry_status(entry)} · {Calendar.strftime(entry.earned_at, "%d %b %Y %H:%M UTC")}
              </p>
            </li>
          </ol>
          <p :if={@points.value.more?}>Showing the latest 50 entries.</p>
        </section>
      </div>
    </article>
    """
  end

  defp actor_name(%{actor_kind: "human"}, _names), do: "You"
  defp actor_name(entry, names), do: Map.get(names, entry.actor_id, "Previously connected agent")

  defp entry_status(%{reversal_of_entry_id: id}) when not is_nil(id), do: "Correction"
  defp entry_status(%{points_micro_delta: 0}), do: "Allowance reached"
  defp entry_status(_), do: "Confirmed"

  defp scope_name("credits"), do: "Credits purchases"
  defp scope_name("activity:human"), do: "Your actions"
  defp scope_name("activity:agent"), do: "Your agents’ actions"
end

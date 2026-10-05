defmodule AshTemplateWeb.ActivityLive do
  @moduledoc """
  What has happened for the signed-in person, newest first: each notification
  (`AshTemplate.Activity.Notification`) with where it leads. The shell reads
  them and reads them again whenever one arrives or is marked read.
  """

  use AshTemplateWeb, :html

  alias AshTemplateWeb.Read
  alias Regent.Primitives

  attr :account, :map, default: nil
  attr :notifications, Read, required: true

  def page(assigns) do
    ~H"""
    <article id="activity-page" class="account-page">
      <header class="account-heading">
        <p class="account-kicker">Home</p>
        <h1 tabindex="-1">Activity</h1>
        <p class="account-lede">
          When someone writes @ and your name in a room, it shows here and on the bell.
        </p>
      </header>

      <section :if={is_nil(@account)} class="account-panel account-signed-out">
        <h2>Sign in to see your activity</h2>
        <p>Mentions of you appear here once you are signed in.</p>
        <Primitives.button type="button" data-account-target="sign-in">Sign in</Primitives.button>
      </section>

      <section :if={@account} class="account-panel activity-panel" aria-labelledby="activity-title">
        <div class="activity-panel__head">
          <h2 id="activity-title">Latest</h2>
          <Primitives.button
            :if={unread?(@notifications)}
            type="button"
            variant="secondary"
            phx-click="mark_all_read"
          >
            Mark all as read
          </Primitives.button>
        </div>
        <p :if={@notifications.state == :loading} class="rg-muted">Loading your activity…</p>
        <Primitives.notice :if={@notifications.state in [:error, :stale]} tone="error">
          Your activity couldn’t be loaded. Refresh the page to try again.
        </Primitives.notice>
        <p :if={@notifications.state == :empty} class="rg-muted">
          Nothing yet. When someone mentions you in a room, it appears here.
        </p>
        <ol :if={@notifications.value not in [nil, []]} class="activity-list">
          <li
            :for={notification <- @notifications.value}
            data-unread={to_string(is_nil(notification.read_at))}
          >
            <.link patch={notification.path}>
              <span class="activity-list__title">
                {notification.title}
                <span :if={is_nil(notification.read_at)} class="activity-list__new">New</span>
              </span>
              <span :if={notification.body} class="activity-list__body">{notification.body}</span>
              <time datetime={DateTime.to_iso8601(notification.inserted_at)}>
                {RegentFormat.relative_time(notification.inserted_at, DateTime.utc_now())}
              </time>
            </.link>
          </li>
        </ol>
      </section>
    </article>
    """
  end

  defp unread?(%Read{value: notifications}) when is_list(notifications),
    do: Enum.any?(notifications, &is_nil(&1.read_at))

  defp unread?(_read), do: false
end

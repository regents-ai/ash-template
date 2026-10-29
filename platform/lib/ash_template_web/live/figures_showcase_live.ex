defmodule AshTemplateWeb.FiguresShowcaseLive do
  @moduledoc """
  Figures every visitor sees alike, working. Base's newest block: one reader
  (`AshTemplate.ChainHead`) asks Base for it once an hour, and again when anyone
  presses the read-again icon (`AshTemplate.ChainRefresh`). Each room's activity: one counter
  (`AshTemplate.Rooms.Activity`) counts a room again when someone posts in it.
  Every open copy of this page shows what `AshTemplate.SharedReading` holds and
  is told when it changes. The page reads the list of rooms once when it opens
  and nothing else from the chain or the database, so a thousand open copies
  cost the one read; a room started while it is open shows after a reload. The `ash-frontend` skill's `public-figures.md` says
  when a product page uses this and when it must not.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplate.{ChainHead, ChainRefresh, Rooms, SharedReading}
  alias AshTemplate.Rooms.Activity
  alias AshTemplateWeb.Components.Shell
  alias Regent.Primitives, as: P

  @key ChainHead.key(8453)

  # Subscribed before the first fetch, so no change between the two is missed.
  @impl true
  def mount(_params, _session, socket) do
    names = for room <- Rooms.list_rooms!(), do: {room.slug, room.name}

    if connected?(socket) do
      SharedReading.subscribe(@key)
      for {slug, _name} <- names, do: SharedReading.subscribe(Activity.key(slug))
    end

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/figures"))
     |> assign(head: head(), names: names)
     |> assign_rooms(), layout: false}
  end

  @impl true
  def handle_info({:shared_reading, @key}, socket), do: {:noreply, assign(socket, head: head())}

  def handle_info({:shared_reading, {:room_activity, _room}}, socket),
    do: {:noreply, assign_rooms(socket)}

  # The new reading arrives as `{:shared_reading, key}`, like any other.
  @impl true
  def handle_event("read_again", _params, socket) do
    ChainRefresh.request(8453)
    {:noreply, socket}
  end

  # No reading yet is shown as the reader being behind, never as a block.
  defp head do
    case SharedReading.fetch(@key) do
      {:ok, %{reading: block, at: at, degraded?: behind?}} ->
        %{block: block, at: at, behind?: behind?}

      :error ->
        %{block: nil, at: nil, behind?: true}
    end
  end

  # Only what a row draws is kept: the room's name and its two figures.
  defp assign_rooms(socket) do
    assign(socket, rooms: Enum.map(socket.assigns.names, &room/1))
  end

  defp room({slug, name}) do
    case SharedReading.fetch(Activity.key(slug)) do
      {:ok, %{reading: %{messages: messages, latest_at: latest_at}, degraded?: behind?}} ->
        %{slug: slug, name: name, messages: messages, latest_at: latest_at, behind?: behind?}

      _no_count_yet ->
        %{slug: slug, name: name, messages: nil, latest_at: nil, behind?: true}
    end
  end

  defp messages(1), do: "1 message"

  defp messages(count),
    do: "#{count |> Integer.to_string() |> RegentFormat.add_delimiters()} messages"

  @impl true
  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main id="figures-page" class="sc onchain-workshop figures-page">
      <header class="sc-header figures-page-header">
        <a class="sc-wordmark" href="/showcase">Ash <span>Workshop</span></a>
        <span :if={@local?} class="sc-local">Local only</span>
        <Shell.theme_toggle id="figures-page-theme" />
      </header>

      <section class="onchain-workshop-intro">
        <p class="sc-eyebrow">Working example</p>
        <h1>Live figures</h1>
        <p>
          Some figures are the same for everyone: a price, a count, the newest block. The site
          reads each one once and shows it on every open page, so a crowd costs no more than one
          visitor.
        </p>
      </section>

      <div class="onchain-workshop-grid">
        <section class="rg-panel rg-panel--surface" aria-labelledby="figures-head-heading">
          <h2 id="figures-head-heading">Latest block</h2>
          <p id="figures-head" class="payments-figure">
            <span id="figures-head-block">{@head.block || "No reading yet"}</span>
            <P.status :if={!@head.behind?} tone="success">Live</P.status>
            <P.status :if={@head.behind?} tone="warning">Behind</P.status>
          </p>
          <P.last_read id="figures-head-read" at={@head.at} phx-click="read_again" />
          <p id="figures-head-state" role="status">
            {if @head.behind?,
              do: "Base can't be read right now. This page catches up by itself.",
              else: "Read from Base once an hour, and again on request."}
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="figures-rooms-heading">
          <h2 id="figures-rooms-heading">Room activity</h2>
          <dl id="figures-rooms" class="payments-terms">
            <div :for={room <- @rooms} id={"figures-room-#{room.slug}"}>
              <dt>{room.name}</dt>
              <dd>
                <span :if={room.messages}>{messages(room.messages)}</span>
                <span :if={!room.messages}>No count yet</span>
                <time :if={room.latest_at} datetime={DateTime.to_iso8601(room.latest_at)}>
                  · latest {Calendar.strftime(room.latest_at, "%-d %b, %H:%M UTC")}
                </time>
                <P.status :if={room.behind?} tone="warning">Behind</P.status>
              </dd>
            </div>
          </dl>
          <p id="figures-rooms-state">Counted once for everyone, when someone posts.</p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="figures-rules-heading">
          <h2 id="figures-rules-heading">Ownership</h2>
          <p>
            Anything that differs from person to person, like your balance or what you may see, is
            still read for you alone.
          </p>
          <p>
            A live figure never holds up a wallet button. If it falls behind, every button still
            works.
          </p>
        </section>
      </div>
    </main>
    """
  end
end

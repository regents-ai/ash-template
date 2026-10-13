defmodule AshTemplateWeb.FiguresShowcaseLive do
  @moduledoc """
  A figure every visitor sees alike, working: Base's newest block. One reader
  (`AshTemplate.ChainHead`) asks Base for it; every open copy of this page shows
  what `AshTemplate.SharedReading` holds and is told when it changes. The page
  reads nothing from the chain or the database itself, so a thousand open
  copies cost the one read. The `ash-frontend` skill's `public-figures.md` says
  when a product page uses this and when it must not.
  """
  use AshTemplateWeb, :live_view

  alias AshTemplate.{ChainHead, SharedReading}
  alias AshTemplateWeb.Components.Shell
  alias Regent.Primitives, as: P

  @key ChainHead.key(8453)

  # Subscribed before the first fetch, so no change between the two is missed.
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SharedReading.subscribe(@key)

    {:ok,
     socket
     |> assign(AshTemplateWeb.PublicDocuments.page("/showcase/figures"))
     |> assign(head: head()), layout: false}
  end

  @impl true
  def handle_info({:shared_reading, @key}, socket), do: {:noreply, assign(socket, head: head())}

  # No reading yet is shown as the reader being behind, never as a block.
  defp head do
    case SharedReading.fetch(@key) do
      {:ok, %{reading: block, degraded?: behind?}} -> %{block: block, behind?: behind?}
      :error -> %{block: nil, behind?: true}
    end
  end

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
          <h2 id="figures-head-heading">Base's newest block</h2>
          <p id="figures-head" class="payments-figure">
            <span id="figures-head-block">{@head.block || "No reading yet"}</span>
            <P.status :if={!@head.behind?} tone="success">Live</P.status>
            <P.status :if={@head.behind?} tone="warning">Behind</P.status>
          </p>
          <p id="figures-head-state" role="status">
            {if @head.behind?,
              do: "Base can't be read right now. This page catches up by itself.",
              else: "Read from Base every two seconds, once for everyone."}
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="figures-rules-heading">
          <h2 id="figures-rules-heading">What stays yours</h2>
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

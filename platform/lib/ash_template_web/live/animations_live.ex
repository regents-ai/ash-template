defmodule AshTemplateWeb.AnimationsLive do
  @moduledoc """
  The motion lab. Every section offers a few versions of one kind of movement
  side by side; the standard one, which the real pages use, is shown until
  another is picked. Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.Motion

  # The versions each section offers.
  @choices %{
    "drawer" => ~w(glide spring lean),
    "sheet" => ~w(rise spring),
    "menu" => ~w(pop drop),
    "note" => ~w(peel toss),
    "toast" => ~w(rise pop side),
    "list" => ~w(glide bounce ripple),
    "count" => ~w(roll tick pop),
    "stamp" => ~w(thunk ink party),
    "tabs" => ~w(glide stretch spring),
    "headline" => ~w(rise cascade type),
    "grid" => ~w(cascade bloom drop)
  }

  @notes [
    "Your report is ready",
    "A teammate joined the project",
    "Your changes were saved",
    "Someone replied to your note",
    "Your export finished",
    "A new sign-in from your phone"
  ]

  @items [
    "Billing",
    "Search",
    "Sign-in",
    "Calendar",
    "Checkout",
    "Settings",
    "Reports",
    "Invites",
    "Exports",
    "Help"
  ]

  @tabs [{"recent", "Recent"}, {"saved", "Saved"}, {"shared", "Shared"}]
  @counts [{"1", "+1"}, {"37", "+37"}, {"1000", "+1,000"}, {"-12", "−12"}]
  @cards ~w(north harbor summit meadow canyon river forest island valley)

  # How long a note stays, and how long an item takes to fade out before the
  # page drops it.
  @note_ms 3_200
  @leave_ms 420

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Motion lab",
       variants: Motion.standard(),
       reduced?: false,
       toasts: [],
       items:
         @items
         |> Enum.take(5)
         |> Enum.with_index(fn name, id -> %{id: id, name: name, leaving?: false} end),
       next_id: 100,
       count: 1_284,
       done?: false,
       tab: "recent"
     )}
  end

  @impl true
  def handle_event("pick", %{"part" => part, "variant" => variant}, socket) do
    if variant in Map.get(@choices, part, []) do
      {:noreply, update(socket, :variants, &Map.put(&1, part, variant))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reduced", _params, socket) do
    {:noreply, update(socket, :reduced?, &(!&1))}
  end

  def handle_event("toast", _params, socket) do
    id = socket.assigns.next_id
    Process.send_after(self(), {:leave, :toasts, id}, @note_ms)
    toast = %{id: id, text: Enum.random(@notes), leaving?: false}

    socket = assign(socket, toasts: socket.assigns.toasts ++ [toast], next_id: id + 1)

    # Three notes at a time: the oldest makes room for the newest.
    case Enum.reject(socket.assigns.toasts, & &1.leaving?) do
      [oldest, _, _, _ | _] -> {:noreply, leave(socket, :toasts, oldest.id)}
      _few -> {:noreply, socket}
    end
  end

  def handle_event("dismiss", %{"id" => id}, socket) do
    {:noreply, leave(socket, :toasts, String.to_integer(id))}
  end

  def handle_event("shuffle", _params, socket) do
    {:noreply, update(socket, :items, &Enum.shuffle/1)}
  end

  def handle_event("sort", _params, socket) do
    {:noreply, update(socket, :items, &Enum.sort_by(&1, fn item -> item.name end))}
  end

  def handle_event("add_item", _params, socket) do
    names = MapSet.new(socket.assigns.items, & &1.name)

    case Enum.reject(@items, &MapSet.member?(names, &1)) do
      [] ->
        {:noreply, socket}

      free ->
        item = %{id: socket.assigns.next_id, name: Enum.random(free), leaving?: false}
        {:noreply, assign(socket, items: [item | socket.assigns.items], next_id: item.id + 1)}
    end
  end

  def handle_event("remove_item", _params, socket) do
    case socket.assigns.items |> Enum.reject(& &1.leaving?) |> List.last() do
      nil -> {:noreply, socket}
      item -> {:noreply, leave(socket, :items, item.id)}
    end
  end

  def handle_event("count", %{"by" => by}, socket) when by in ["1", "37", "1000", "-12"] do
    {:noreply, update(socket, :count, &max(&1 + String.to_integer(by), 0))}
  end

  # The stamp is told to land only once the work is marked done.
  def handle_event("finish", _params, socket) do
    {:noreply, socket |> assign(done?: true) |> push_event("motion:done", %{})}
  end

  def handle_event("reopen", _params, socket) do
    {:noreply, assign(socket, done?: false)}
  end

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["recent", "saved", "shared"] do
    {:noreply, assign(socket, tab: tab)}
  end

  @impl true
  def handle_info({:leave, key, id}, socket), do: {:noreply, leave(socket, key, id)}

  def handle_info({:drop, key, id}, socket) do
    {:noreply, update(socket, key, &Enum.reject(&1, fn item -> item.id == id end))}
  end

  # An item is hidden first, so it can fade out while its neighbours close
  # the gap, and dropped once that is over.
  defp leave(socket, key, id) do
    Process.send_after(self(), {:drop, key, id}, @leave_ms)
    update(socket, key, fn items -> Enum.map(items, &hide(&1, id)) end)
  end

  defp hide(%{id: id} = item, id), do: %{item | leaving?: true}
  defp hide(item, _id), do: item

  defp commas(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, tabs: @tabs, counts: @counts, cards: @cards)

    ~H"""
    <main id="motion-lab" class="motion-lab" data-motion={@reduced? && "reduced"}>
      <header class="motion-lab__head">
        <p class="motion-lab__kicker"><a href={~p"/"}>Ash Template</a> / Motion lab</p>
        <h1>Motion lab</h1>
        <p class="motion-lab__lede">
          Little movements, side by side. The version marked standard is the one the real pages
          use; the others stay here to compare. Press things and switch between them.
        </p>
        <div class="motion-lab__row">
          <Regent.Primitives.button variant="secondary" phx-click={JS.dispatch("lab:replay")}>
            Replay everything
          </Regent.Primitives.button>
          <Regent.Primitives.button
            variant="secondary"
            phx-click="reduced"
            aria-pressed={to_string(@reduced?)}
          >
            Less motion
          </Regent.Primitives.button>
        </div>
      </header>

      <.section number="1" id="presses" title="Presses">
        <:lede>
          A mouse or finger press gets a small answer. Pressing Enter or Space works the same,
          just without the show. Every button squishes, and one that says no shakes its head.
        </:lede>
        <div id="lab-presses" class="motion-lab__row" phx-hook="LabPress">
          <Regent.Primitives.button variant="secondary" data-press="squish">
            Squish<.standard />
          </Regent.Primitives.button>
          <Regent.Primitives.button variant="secondary" data-press="jelly">
            Jelly
          </Regent.Primitives.button>
          <Regent.Primitives.button variant="secondary" data-press="sparks">
            Sparks
          </Regent.Primitives.button>
          <Regent.Primitives.button variant="secondary" data-press="ping">
            Ping
          </Regent.Primitives.button>
          <Regent.Primitives.button variant="secondary" data-press="stitches">
            Stitches
          </Regent.Primitives.button>
          <Regent.Primitives.button variant="secondary" data-press="nope">
            Nope<.standard />
          </Regent.Primitives.button>
        </div>
      </.section>

      <.section number="2" id="slides" title="Panels that slide">
        <:lede>Open and close each one a few times. Escape closes the one on top.</:lede>
        <dl class="motion-lab__pickers">
          <div :for={
            {part, label} <- [
              {"drawer", "Drawer"},
              {"sheet", "Sheet"},
              {"menu", "Menu"},
              {"note", "Note"}
            ]
          }>
            <dt>{label}</dt>
            <dd><.picker part={part} variants={@variants} /></dd>
          </div>
        </dl>
        <.slides variants={@variants} />
      </.section>

      <.section number="3" id="changes" title="Things that change">
        <:lede>
          Each of these waits for the page to decide, then moves from the old picture to the new one.
        </:lede>
        <div class="motion-lab__grid">
          <article class="motion-lab__card">
            <h3>Notes that pop up</h3>
            <.picker part="toast" variants={@variants} />
            <div class="motion-lab__stage">
              <Regent.Primitives.button variant="secondary" phx-click="toast">
                Send a note
              </Regent.Primitives.button>
              <div class="motion-lab__toast-dock">
                <ol
                  id="lab-toasts"
                  class="motion-lab__toasts"
                  phx-hook="LabList"
                  data-layout-id="lab-toasts"
                  data-children="[data-toast]"
                  data-variant={@variants["toast"]}
                  aria-live="polite"
                >
                  <li
                    :for={toast <- @toasts}
                    id={"lab-toast-#{toast.id}"}
                    class="motion-lab__toast"
                    data-toast
                    data-layout-id={"lab-toast-#{toast.id}"}
                    hidden={toast.leaving?}
                  >
                    <span>{toast.text}</span>
                    <button
                      type="button"
                      phx-click="dismiss"
                      phx-value-id={toast.id}
                      aria-label="Dismiss"
                    >
                      ×
                    </button>
                  </li>
                </ol>
              </div>
            </div>
          </article>

          <article class="motion-lab__card">
            <h3>A list that rearranges</h3>
            <.picker part="list" variants={@variants} />
            <div class="motion-lab__row motion-lab__row--tight">
              <Regent.Primitives.button variant="secondary" phx-click="shuffle">
                Shuffle
              </Regent.Primitives.button>
              <Regent.Primitives.button variant="secondary" phx-click="sort">
                A to Z
              </Regent.Primitives.button>
              <Regent.Primitives.button variant="secondary" phx-click="add_item">
                Add one
              </Regent.Primitives.button>
              <Regent.Primitives.button variant="secondary" phx-click="remove_item">
                Take one away
              </Regent.Primitives.button>
            </div>
            <ul
              id="lab-items"
              class="motion-lab__items"
              phx-hook="LabList"
              data-layout-id="lab-items"
              data-children="[data-item-chip]"
              data-variant={@variants["list"]}
            >
              <li
                :for={item <- @items}
                id={"lab-item-#{item.id}"}
                data-item-chip
                data-layout-id={"lab-item-#{item.id}"}
                hidden={item.leaving?}
              >
                {item.name}
              </li>
            </ul>
          </article>

          <article class="motion-lab__card">
            <h3>A number that turns over</h3>
            <.picker part="count" variants={@variants} />
            <p
              id="lab-count"
              class="motion-lab__count"
              phx-hook="LabCount"
              data-variant={@variants["count"]}
            >
              <span data-count>{commas(@count)}</span>
              <span class="motion-lab__count-label">visits this week</span>
            </p>
            <div class="motion-lab__row motion-lab__row--tight">
              <Regent.Primitives.button
                :for={{by, label} <- @counts}
                variant="secondary"
                phx-click="count"
                phx-value-by={by}
              >
                {label}
              </Regent.Primitives.button>
            </div>
          </article>

          <article class="motion-lab__card">
            <h3>Work marked done</h3>
            <.picker part="stamp" variants={@variants} />
            <div
              id="lab-stamp"
              class="motion-lab__task"
              phx-hook="LabStamp"
              data-variant={@variants["stamp"]}
            >
              <p class="motion-lab__kicker">Task</p>
              <h4>Send the monthly report</h4>
              <p>2 comments · due Friday</p>
              <div :if={@done?} class="motion-lab__stamp" data-stamp>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path data-tick d="M4 12.5l5 5L20 6.5" /></svg>
                Done
              </div>
              <Regent.Primitives.button
                variant="secondary"
                phx-click={if @done?, do: "reopen", else: "finish"}
              >
                {if @done?, do: "Reopen", else: "Mark as done"}
              </Regent.Primitives.button>
            </div>
          </article>
        </div>
      </.section>

      <.section number="4" id="views" title="Moving between views">
        <:lede>
          The underline travels to the tab you pick and the new view slides in the same way.
        </:lede>
        <.picker part="tabs" variants={@variants} />
        <div
          id="lab-tabs"
          class="motion-lab__tabs"
          phx-hook="LabTabs"
          data-active={@tab}
          data-variant={@variants["tabs"]}
        >
          <div class="motion-lab__tablist" role="tablist" aria-label="Library views">
            <button
              :for={{key, label} <- @tabs}
              type="button"
              role="tab"
              id={"lab-tab-#{key}"}
              data-tab={key}
              aria-selected={to_string(@tab == key)}
              aria-controls={@tab == key && "lab-tabpanel-#{key}"}
              phx-click="tab"
              phx-value-tab={key}
            >
              {label}
            </button>
            <span
              class="motion-lab__ink"
              data-ink
              aria-hidden="true"
              phx-mounted={JS.ignore_attributes(["style"])}
            ></span>
          </div>
          <div
            id={"lab-tabpanel-#{@tab}"}
            class="motion-lab__tabpanel"
            role="tabpanel"
            aria-labelledby={"lab-tab-#{@tab}"}
          >
            <ul :if={@tab == "recent"}>
              <li>Quarterly plan</li>
              <li>Team offsite notes</li>
              <li>Customer interviews</li>
            </ul>
            <ul :if={@tab == "saved"}>
              <li>Pricing ideas</li>
              <li>Launch checklist</li>
            </ul>
            <ul :if={@tab == "shared"}>
              <li>Design review · 4 people</li>
              <li>Roadmap · 9 people</li>
              <li>Support guide · 2 people</li>
              <li>Hiring plan · 3 people</li>
            </ul>
          </div>
        </div>
      </.section>

      <.section number="5" id="arriving" title="Arriving">
        <:lede>How a headline and a page of cards first appear.</:lede>
        <div class="motion-lab__grid motion-lab__grid--wide">
          <article class="motion-lab__card">
            <h3>Headline</h3>
            <.picker part="headline" variants={@variants} />
            <div
              id="lab-headline"
              class="motion-lab__headline"
              phx-hook="LabHeadline"
              phx-update="ignore"
              data-variant={@variants["headline"]}
            >
              <p data-headline>Build something people love.</p>
              <Regent.Primitives.button variant="secondary" data-replay>Replay</Regent.Primitives.button>
            </div>
          </article>

          <article class="motion-lab__card">
            <h3>Cards</h3>
            <.picker part="grid" variants={@variants} />
            <div
              id="lab-cards"
              class="motion-lab__cascade"
              phx-hook="LabCascade"
              phx-update="ignore"
              data-variant={@variants["grid"]}
            >
              <ul>
                <li :for={card <- @cards} data-card>
                  <span aria-hidden="true">{card |> String.first() |> String.upcase()}</span>
                  {String.capitalize(card)}
                </li>
              </ul>
              <Regent.Primitives.button variant="secondary" data-replay>Replay</Regent.Primitives.button>
            </div>
          </article>
        </div>
      </.section>

      <div id="motion-lab-fx" class="motion-lab__fx" phx-update="ignore" aria-hidden="true"></div>
    </main>
    """
  end

  attr :number, :string, required: true
  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :lede, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="motion-lab__section" aria-labelledby={"lab-#{@id}-title"}>
      <header class="motion-lab__section-head">
        <h2 id={"lab-#{@id}-title"}><span>{@number}</span> {@title}</h2>
        <p>{render_slot(@lede)}</p>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :part, :string, required: true
  attr :variants, :map, required: true

  defp picker(assigns) do
    assigns = assign(assigns, :choices, Map.fetch!(@choices, assigns.part))

    ~H"""
    <div class="motion-lab__picker" role="group" aria-label="Versions">
      <button
        :for={variant <- @choices}
        type="button"
        phx-click="pick"
        phx-value-part={@part}
        phx-value-variant={variant}
        aria-pressed={to_string(@variants[@part] == variant)}
      >
        {variant}<.standard :if={Motion.standard(@part) == variant} />
      </button>
    </div>
    """
  end

  defp standard(assigns) do
    ~H"""
    <span class="motion-lab__standard">standard</span>
    """
  end

  attr :variants, :map, required: true

  # The lab owns these panels outright, so the page never patches inside
  # them; it keeps only the versions on the island current.
  defp slides(assigns) do
    ~H"""
    <div
      id="lab-slides"
      class="motion-lab__slides"
      phx-hook="LabSlides"
      phx-update="ignore"
      data-drawer={@variants["drawer"]}
      data-sheet={@variants["sheet"]}
      data-menu={@variants["menu"]}
      data-note={@variants["note"]}
    >
      <div class="motion-lab__row">
        <div class="motion-lab__menu-anchor">
          <Regent.Primitives.button
            variant="secondary"
            data-open="menu"
            aria-expanded="false"
            aria-controls="lab-menu"
          >
            Share <span aria-hidden="true">▾</span>
          </Regent.Primitives.button>
          <div id="lab-menu" class="motion-lab__menu" data-lab-panel="menu" hidden>
            <button type="button" data-item data-close>Copy link</button>
            <button type="button" data-item data-close>Invite a teammate</button>
            <button type="button" data-item data-close>Save for later</button>
          </div>
        </div>
        <Regent.Primitives.button
          variant="secondary"
          data-open="drawer"
          aria-expanded="false"
          aria-controls="lab-drawer"
        >
          Open the drawer
        </Regent.Primitives.button>
        <Regent.Primitives.button
          variant="secondary"
          data-open="sheet"
          aria-expanded="false"
          aria-controls="lab-sheet"
        >
          Pull up a sheet
        </Regent.Primitives.button>
        <Regent.Primitives.button
          variant="secondary"
          data-open="note"
          aria-expanded="false"
          aria-controls="lab-note"
        >
          Pin a note
        </Regent.Primitives.button>
      </div>

      <div class="motion-lab__shade" data-shade hidden></div>

      <aside
        id="lab-drawer"
        class="motion-lab__drawer"
        data-lab-panel="drawer"
        role="dialog"
        aria-labelledby="lab-drawer-title"
        hidden
      >
        <header>
          <h3 id="lab-drawer-title">Project details</h3>
          <button type="button" class="motion-lab__close" data-close aria-label="Close">×</button>
        </header>
        <p data-item>The launch page needs a final review.</p>
        <p data-item>3 comments · 2 people assigned · updated 4 hours ago</p>
        <p data-item>Next step: check the pricing table, then publish.</p>
      </aside>

      <section
        id="lab-sheet"
        class="motion-lab__sheet"
        data-lab-panel="sheet"
        role="dialog"
        aria-labelledby="lab-sheet-title"
        hidden
      >
        <header>
          <h3 id="lab-sheet-title">What would you like to do?</h3>
          <button type="button" class="motion-lab__close" data-close aria-label="Close">×</button>
        </header>
        <ul>
          <li data-item>Start a new project</li>
          <li data-item>Open a recent file</li>
          <li data-item>Invite your team</li>
        </ul>
      </section>

      <div id="lab-note" class="motion-lab__note" data-lab-panel="note" hidden>
        <p>Remember to thank the team for the launch.</p>
        <button type="button" class="motion-lab__close" data-close>Unpin</button>
      </div>
    </div>
    """
  end
end

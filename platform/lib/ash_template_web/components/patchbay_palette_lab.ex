defmodule AshTemplateWeb.PatchbayPaletteLab do
  @moduledoc "Local color studies of the Patchbay homepage, using fixed sample content."
  use AshTemplateWeb, :html
  alias Regent.Primitives, as: P

  @palettes [
    %{
      id: "porcelain",
      name: "Porcelain / cobalt",
      description: "Crisp porcelain, cool ink, a confident cobalt.",
      number: "01"
    },
    %{
      id: "kiln",
      name: "Kiln / vermilion",
      description: "Warm paper and fired clay. Familiar, with a little heat.",
      number: "02"
    },
    %{
      id: "tidal",
      name: "Tidal / sea glass",
      description: "Chalky greens, deep seawater, a quiet mint accent.",
      number: "03"
    },
    %{
      id: "orchid",
      name: "Orchid / plum",
      description: "An almost-white lilac with rich, inky plum.",
      number: "04"
    },
    %{
      id: "graphite",
      name: "Graphite / ice",
      description: "Neutral graphite with a precise glacial blue.",
      number: "05"
    },
    %{
      id: "rosewood",
      name: "Rosewood / blush",
      description: "Soft rose, wine-dark ink, and restrained warmth.",
      number: "06"
    },
    %{
      id: "olive",
      name: "Olive / chartreuse",
      description: "Linen and olive by day; deep moss and citron after dark.",
      number: "07"
    },
    %{
      id: "brass",
      name: "Ink / brass",
      description: "Ivory, blue-black, and an understated metallic warmth.",
      number: "08"
    },
    %{
      id: "iris",
      name: "Iris / periwinkle",
      description: "Pale lavender, violet ink, and luminous periwinkle.",
      number: "09"
    },
    %{
      id: "espresso",
      name: "Espresso / apricot",
      description: "Oat milk and coffee, finished with a soft apricot.",
      number: "10"
    }
  ]

  def palette(id), do: Enum.find(@palettes, &(&1.id == id)) || hd(@palettes)
  def view(mode) when mode in ~w(both light dark), do: mode
  def view(_mode), do: "both"

  attr :palette, :map, required: true
  attr :view, :string, required: true

  def content(assigns) do
    assigns =
      assign(assigns,
        palettes: @palettes,
        modes: if(assigns.view == "both", do: ~w(light dark), else: [assigns.view])
      )

    ~H"""
    <section id="patchbay-palettes" class="pb-lab" aria-labelledby="pb-lab-title">
      <header class="pb-lab__intro">
        <p class="motion-lab__kicker">Color studies / 10 directions × 2 themes</p>
        <h2 id="pb-lab-title">Ten palettes. Light and dark.</h2>
        <p>
          Explore the current homepage in ten new color directions. Select a theme to expand it.
        </p>
      </header>
      <nav class="pb-lab__choices" aria-label="Patchbay color palettes">
        <.link
          :for={option <- @palettes}
          patch={~p"/animations?lab=palettes&palette=#{option.id}&view=#{@view}"}
          class="pb-lab__choice"
          aria-current={option.id == @palette.id && "true"}
        >
          <span class="pb-lab__choice-top"><span>{option.number}</span><span :if={
            option.id == @palette.id
          }>Selected ✓</span></span>
          <span class="pb-lab__samples" aria-hidden="true">
            <span
              :for={mode <- ~w(light dark)}
              class="pb-palette pb-lab__sample"
              data-palette={option.id}
              data-mode={mode}
            >
              <i></i><i></i><i></i><i></i>
            </span>
          </span>
          <strong>{option.name}</strong>
        </.link>
      </nav>
      <div class="pb-lab__toolbar">
        <div aria-live="polite">
          <h3>{@palette.number} / {@palette.name}</h3>
          <p>{@palette.description}</p>
        </div>
        <nav class="pb-lab__views" aria-label="Preview appearance">
          <.link
            :for={{mode, label} <- [{"both", "Side by side"}, {"light", "Light"}, {"dark", "Dark"}]}
            patch={~p"/animations?lab=palettes&palette=#{@palette.id}&view=#{mode}"}
            aria-current={@view == mode && "true"}
          >{label}</.link>
        </nav>
      </div>
      <p class="pb-lab__caption">
        Homepage mockup · sample content · buttons only show a local preview notice
      </p>
      <div class="pb-lab__previews" data-view={@view}>
        <article
          :for={mode <- @modes}
          class="pb-palette pb-preview"
          data-palette={@palette.id}
          data-mode={mode}
          aria-label={"#{@palette.name} — #{mode} homepage preview"}
        >
          <header class="pb-preview__label">
            <span>{String.capitalize(mode)}</span><span>{@palette.name}</span>
          </header>
          <.homepage mode={mode} />
          <div class="pb-preview__tokens" aria-label={"#{mode} palette colors"}>
            <div :for={
              {role, label} <- [
                {"ground", "Canvas"},
                {"surface", "Surface"},
                {"ink", "Text"},
                {"muted", "Muted"},
                {"line", "Border"},
                {"accent", "Accent"}
              ]
            }>
              <i data-role={role} aria-hidden="true"></i><span>{label}</span>
            </div>
          </div>
        </article>
      </div>
    </section>
    """
  end

  attr :mode, :string, required: true

  defp homepage(assigns) do
    assigns =
      assign(assigns,
        sites: [
          {"T", "Target", "1 tool"},
          {"O", "OpenAI", "1 tool"},
          {"m", "Monday", "1 tool"},
          {"A", "ASUS", "7 tools"},
          {"r", "redBus", "2 tools"},
          {"B", "Bitdefender", "0 tools"},
          {"F", "Fever", "5 tools"},
          {"O", "OpenAI Developers", "5 tools"}
        ],
        questions: [
          %{
            title: "How do I find the right WebMCP tool for a page?",
            site: "Patchbay",
            author: "Mira",
            time: "12 min ago",
            replies: "3 replies",
            views: "42 views",
            solved: true
          },
          %{
            title: "Can an agent keep my cart between sessions?",
            site: "Shopify",
            author: "Atlas",
            time: "38 min ago",
            replies: "2 replies",
            views: "28 views",
            solved: false
          },
          %{
            title: "A better way to confirm that a tool call worked",
            site: "OpenAI",
            author: "Noor",
            time: "1 hour ago",
            replies: "5 replies",
            views: "67 views",
            solved: true
          }
        ]
      )

    ~H"""
    <div class="pb-home">
      <div class="pb-home__nav">
        <span class="pb-home__brand"><svg
          viewBox="0 0 16 16"
          width="16"
          height="16"
          fill="currentColor"
          aria-hidden="true"
        ><path d="M1 3h3v3H1zm5 0h3v3H6zm5 0h3v3h-3zM1 8h13v5H1z" /></svg>Patchbay</span>
        <span class="pb-home__search">Search <kbd>⌘K</kbd></span>
        <span class="pb-home__nav-items">Questions <span>Sites</span> <span>Offers</span></span>
        <P.button
          variant="secondary"
          class="pb-home__button pb-home__ask"
          phx-click={JS.show(to: "#pb-preview-notice-#{@mode}")}
        >Ask a question</P.button>
      </div>
      <div class="pb-home__body">
        <section class="pb-home__hero" aria-label="Ask Patchbay">
          <h4>Agents post to get unstuck fast</h4>
          <div class="pb-home__crowd" aria-hidden="true">
            <img
              :for={shape <- ~w(triangle squircle drop circle-blue circle-ink)}
              src={"/images/lab/patchbay/#{shape}.svg"}
              alt=""
              width="36"
              height="36"
            />
          </div>
          <div class="pb-home__composer">
            <label class="pb-home__field"><span class="visually-hidden">Preview question, read only</span><input
              readonly
              value=""
              placeholder="Ask about a WebMCP tool"
            /></label>
            <P.button
              variant="secondary"
              class="pb-home__button pb-home__fix"
              phx-click={JS.show(to: "#pb-preview-notice-#{@mode}")}
            >Fix it free</P.button>
            <P.button
              variant="secondary"
              class="pb-home__button pb-home__post"
              phx-click={JS.show(to: "#pb-preview-notice-#{@mode}")}
            >Post to the forum</P.button>
          </div>
          <p
            id={"pb-preview-notice-#{@mode}"}
            class="pb-home__notice"
            role="status"
            style="display: none;"
          >
            This is a color preview. No question was posted.
          </p>
        </section>
        <section class="pb-home__directory" aria-label="Popular sites preview">
          <div class="pb-home__section-head">
            <h4>Most Popular WebMCP Sites</h4><span>All sites →</span>
          </div>
          <div class="pb-home__sites">
            <div :for={{mark, name, tools} <- @sites} class="pb-home__site">
              <span class="pb-home__site-mark" aria-hidden="true">{mark}</span>
              <strong>{name}</strong><small>{tools}</small>
            </div>
          </div>
        </section>
        <div class="pb-home__feed-tabs" aria-label="Question feed preview">
          <strong>Recent</strong><span>Popular</span><span>Unanswered</span><span>Solved</span><span>Following</span>
        </div>
        <div class="pb-home__feed">
          <aside class="pb-home__sidebar">
            <p>Featured sites</p>
            <span
              :for={site <- ~w(Shopify Patchbay Target)}
              class={site == "Patchbay" && "is-current"}
            >{site}<b :if={site == "Patchbay"}>↗</b></span>
            <p>Sites</p><span :for={site <- ~w(OpenAI Monday ASUS redBus)}>{site}</span>
          </aside>
          <section class="pb-home__questions" aria-label="Sample questions">
            <div class="pb-home__feed-title">Recent <span>All questions</span></div>
            <article :for={question <- @questions} class="pb-home__question">
              <div class="pb-home__question-meta">
                <span>{question.site}</span><span :if={question.solved} class="pb-home__solved">✓ Solved</span>
              </div>
              <h5>{question.title}</h5>
              <p>{question.author} · {question.time}</p>
              <div class="pb-home__question-stats">
                <span>{question.replies}</span><span>{question.views}</span>
              </div>
            </article>
          </section>
        </div>
        <footer class="pb-home__footer">
          <span>Get started with your agent</span><span>Docs · About · Help</span>
        </footer>
      </div>
    </div>
    """
  end
end

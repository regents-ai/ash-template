defmodule AshTemplateWeb.Components.CodeCube do
  @moduledoc """
  The world cube's twin: a turning cube whose six faces are screens of falling
  code, one for each Regent site and one for siwa-server, each opening a card.

  The server renders one button for each face, and those buttons are the whole
  cube wherever it cannot be drawn: no WebGPU, no JavaScript, or a visitor who
  asked for less motion. Where it can, the `CodeCube` hook draws the cube on the
  stage and a click on a face presses that face's button. The buttons stay in
  reach of the keyboard and show while one has focus.

  A face's card lists the browser tools that site offers agents, or, for
  siwa-server, how an agent connects to it. The page owns the read behind it and
  hands the card where the read stands.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # Each face and the site it stands for. The face fixes the code the renderer
  # draws on it: 0 amber, 1 magenta hex, 2 cyan binary, 3 gold dots on blue,
  # 4 green, 5 ice blue.
  # A site's card opens its agent guide; siwa-server's opens its code.
  @faces [
    %{face: 4, site: "regents", name: "regents.sh", link: "regents.sh/agents.md"},
    %{face: 0, site: "patchbay", name: "patchbay.help", link: "patchbay.help/agents.md"},
    %{face: 2, site: "techtree", name: "techtree.sh", link: "techtree.sh/agents.md"},
    %{face: 1, site: "autolaunch", name: "autolaunch.sh", link: "autolaunch.sh/agents.md"},
    %{face: 3, site: "keyfleet", name: "keyfleet.ai", link: "keyfleet.ai/agents.md"},
    %{face: 5, site: "siwa", name: "siwa-server", link: "github.com/regents-ai/siwa-server"}
  ]

  @doc """
  The six faces, each a map with `:face` (the cube face), `:site` (sent with a
  click as `site`), `:name`, the site's address as people know it, and `:link`,
  the page its card opens, without `https://`.
  """
  def faces, do: @faces

  @doc "The face for a site key, or nil for a key no face has."
  def face(site), do: Enum.find(@faces, &(&1.site == site))

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :click, :string, required: true, doc: "The event a face's button sends."

  def cube(assigns) do
    assigns = assign(assigns, :faces, @faces)

    ~H"""
    <section
      id={@id}
      class="code-cube"
      aria-label={@label}
      phx-hook="CodeCube"
      phx-mounted={JS.ignore_attributes(["data-code-ready"])}
    >
      <div id={"#{@id}-stage"} class="code-cube__stage" phx-update="ignore" aria-hidden="true">
        <canvas class="code-cube__canvas" data-code-canvas></canvas>
        <p class="code-cube__caption" data-code-caption></p>
      </div>
      <p class="code-cube__hint">Drag to turn. Click a side for its tools.</p>
      <ul class="code-cube__faces">
        <li :for={face <- @faces}>
          <button
            type="button"
            class="code-cube__face"
            data-code-face={face.face}
            data-code-site={face.site}
            data-code-name={face.name}
            phx-click={@click}
            phx-value-site={face.site}
          >
            {face.name}
          </button>
        </li>
      </ul>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :face, :map, required: true, doc: "The face whose card this is, from `faces/0`."

  attr :state, :atom,
    required: true,
    doc: "Where the read of the site's tools stands: :loading, :ready, :empty or :error."

  attr :tools, :list,
    default: [],
    doc: "The site's tools, each with :name, :title and :description."

  attr :help, :map, default: nil, doc: "siwa-server's steps, for its face."
  attr :close, :string, required: true, doc: "The event sent when the card closes."
  attr :retry, :string, required: true, doc: "The event a Try again press sends, with `site`."

  @doc """
  A face's card: a modal that opens as it is rendered, scrolls what it lists and
  closes with its X or Escape.
  """
  def card(assigns) do
    ~H"""
    <Regent.Structure.dialog
      id={@id}
      class="code-card"
      data-face={@face.face}
      aria-labelledby={"#{@id}-title"}
      phx-hook="InfoDialog"
      data-open
      data-close-event={@close}
    >
      <header class="code-card__head">
        <h2 id={"#{@id}-title"}>{title(@face, @state, @tools)}</h2>
        <a
          href={"https://#{@face.link}"}
          class="code-card__link"
          target="_blank"
          rel="noopener noreferrer"
        >
          {link_label(@face)}
          <span aria-hidden="true">↗</span><span class="visually-hidden">, opens in a new tab</span>
        </a>
        <form method="dialog">
          <button type="submit" class="code-card__close" aria-label="Close">
            <svg viewBox="0 0 16 16" aria-hidden="true">
              <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
            </svg>
          </button>
        </form>
      </header>
      <div class="code-card__body">
        <.connection :if={@face.site == "siwa"} help={@help} />
        <.tools
          :if={@face.site != "siwa"}
          face={@face}
          state={@state}
          tools={@tools}
          retry={@retry}
        />
      </div>
    </Regent.Structure.dialog>
    """
  end

  defp tools(%{state: :ready} = assigns) do
    ~H"""
    <ol class="code-card__list">
      <li :for={tool <- @tools} class="code-card__tool">
        <h3>{tool.title}</h3>
        <code>{tool.name}</code>
        <p>{tool.description}</p>
      </li>
    </ol>
    """
  end

  defp tools(%{state: :empty} = assigns) do
    ~H"""
    <p class="code-card__note">{@face.name} offers agents no tools here right now.</p>
    """
  end

  defp tools(%{state: :error} = assigns) do
    ~H"""
    <p class="code-card__note">
      {@face.name}'s tools could not be read right now. Try again in a minute.
    </p>
    <button type="button" class="rg-button" phx-click={@retry} phx-value-site={@face.site}>
      <span class="rg-button__label">Try again</span>
    </button>
    """
  end

  defp tools(%{state: :loading} = assigns) do
    ~H"""
    <p class="code-card__note">Reading {@face.name}'s tools…</p>
    """
  end

  defp connection(assigns) do
    ~H"""
    <p class="code-card__note">One sign-in for agents on every Regent site.</p>
    <ol class="code-card__list">
      <li :for={step <- @help.steps} class="code-card__tool">
        <h3>{step.title}</h3>
        <p>{step.copy}</p>
        <pre><code>{step.command}</code></pre>
      </li>
    </ol>
    <a href={@help.guide} class="rg-button" target="_blank" rel="noopener noreferrer">
      <span class="rg-button__label">
        Read the whole guide<span class="visually-hidden">, opens in a new tab</span>
      </span>
    </a>
    """
  end

  defp title(%{site: "siwa"} = face, _state, _tools), do: "#{face.name} : Connect an agent"
  defp title(face, :ready, tools), do: "#{face.name} : #{length(tools)} WebMCP Tools"
  defp title(face, _state, _tools), do: "#{face.name} : WebMCP Tools"

  defp link_label(%{site: "siwa"}), do: "Open GitHub"
  defp link_label(_face), do: "Open agents.md"
end

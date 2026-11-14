defmodule AshTemplateWeb.IconsLabLive do
  @moduledoc """
  Icons: fifty-six small diagrams, each one a word, each on its own short loop, in
  seven sections. Thirty-two follow a reference sheet of diagram icons; twenty-four
  say what Regents products do.

  The words and their numbers are the page's own text, a list per section, and each
  cell can be focused from the keyboard. The drawings are one GPU picture behind the
  whole sheet (the `IconSheet` hook, one canvas island); each drawing is data in
  `assets/js/icon_sheet/icons/`, under the name the cell carries in `data-icon`.
  Nothing here reads or changes anything outside the page.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplateWeb.PublicDocuments

  @groups [
    {"connect", "Connect", ~w(merge converge hierarchy spread relay handshake mesh bridge)},
    {"signals", "Signals", ~w(influence broadcast signal noise sync tempo scan detect)},
    {"flow", "Flow", ~w(queue prioritize route reroute filter escalate cycle fuse)},
    {"control", "Control", ~w(shield isolate encrypt hold contain balance align consensus)},
    {"agents", "Agents", ~w(ask answer tool skill eval train cite fork)},
    {"capital", "Capital", ~w(stake claim share treasury raise launch cover strike)},
    {"fleets", "Fleets", ~w(pair key fleet patch poll propose vote crown)}
  ]

  # Each icon's number runs on from the section before.
  @sections @groups
            |> Enum.map_reduce(1, fn {id, title, names}, first ->
              icons =
                names
                |> Enum.with_index(first)
                |> Enum.map(fn {name, number} ->
                  %{
                    id: name,
                    word: String.capitalize(name),
                    number: number |> Integer.to_string() |> String.pad_leading(2, "0")
                  }
                end)

              {%{id: id, title: title, icons: icons}, first + length(names)}
            end)
            |> elem(0)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(PublicDocuments.page(~p"/animations/icons"))
     |> assign(sections: @sections)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="icons-lab" class="motion-lab motion-lab--icons">
      <header class="motion-lab__head">
        <p class="motion-lab__kicker">
          <a href={~p"/"}>Ash Template</a> / <a href={~p"/animations"}>Motion lab</a> / Icons
        </p>
        <h1>Icons</h1>
        <p class="motion-lab__lede">Each small diagram says one word, in a loop of a few seconds.</p>
      </header>

      <div
        id="icons-sheet"
        class="icons-lab"
        phx-hook="IconSheet"
        phx-mounted={JS.ignore_attributes(["data-icons-ready"])}
      >
        <div id="icons-sheet-stage" class="icons-lab__stage" phx-update="ignore">
          <canvas
            data-icons-canvas
            role="img"
            aria-label="A small moving diagram above each word in the lists below."
          ></canvas>
        </div>

        <p class="icons-lab__note">The drawings need a newer browser.</p>

        <section
          :for={section <- @sections}
          id={"icons-#{section.id}"}
          class="icons-lab__section"
          aria-labelledby={"icons-#{section.id}-title"}
        >
          <h2 id={"icons-#{section.id}-title"} class="icons-lab__title">{section.title}</h2>
          <ul class="icons-lab__grid">
            <li :for={icon <- section.icons} class="icon-cell" tabindex="0" data-icon={icon.id}>
              <span class="icon-cell__art" data-icon-art></span>
              <span class="icon-cell__word">{icon.word}</span>
              <span class="icon-cell__number">{icon.number}</span>
            </li>
          </ul>
        </section>
      </div>
    </main>
    """
  end
end

defmodule AshTemplateWeb.Components.AgentTools do
  @moduledoc """
  The WebMCP tools every page offers an agent, read when this module compiles
  from `priv/tool_manifest.json`, the file the pages register them from
  (`assets/js/public_tools.ts` offers the entries scoped to the site). The bottom
  bar's button says how many there are and opens a dialog listing each tool with
  its description, which copies the whole list as Markdown, or every Regent
  site's tools at once.
  """

  use Phoenix.Component

  alias AshTemplate.SiteTools

  manifest = Application.app_dir(:ash_template, "priv/tool_manifest.json")
  @external_resource manifest

  @tools (for %{"scope" => "site"} = tool <-
                manifest |> File.read!() |> Jason.decode!() |> Map.fetch!("tools") do
            %{name: tool["name"], title: tool["title"], description: tool["description"]}
          end)

  @count "#{length(@tools)} WebMCP Tools"
  @label "Agents see #{@count}"

  @markdown """
  # Ash Template: #{@label}

  #{Enum.map_join(@tools, "\n\n", &"## #{&1.title}\n\n`#{&1.name}`\n\n#{&1.description}")}
  """

  attr :id, :string, required: true
  attr :dialog, :string, required: true, doc: "The id of the `dialog/1` it opens."

  @doc """
  The button naming how many tools agents see, which opens their list. A phone
  shows only the count.
  """
  def button(assigns) do
    assigns = assign(assigns, label: @label, count: @count)

    ~H"""
    <button
      id={@id}
      class="agent-tools-button"
      type="button"
      aria-haspopup="dialog"
      aria-controls={@dialog}
      aria-label={@label}
      data-agent-tools-open
    >
      <span class="agent-tools-button__lead">Agents see</span> {@count}
    </button>
    """
  end

  attr :id, :string, required: true

  @doc """
  The dialog listing every tool, closed with its X, Escape or a press beside it.
  Besides the copy of its own list, it copies every Regent site's tools at once,
  which the page reads each time the dialog opens until one read succeeds
  (`assets/js/agent_tools.ts`); until then that button waits, and the line
  under it says how the read stands. Everything in it is fixed when the page is
  built, so the page never redraws it: an opening, and what the read put in it,
  last through the page connecting and every later update.
  """
  def dialog(assigns) do
    assigns =
      assign(assigns,
        label: @label,
        tools: @tools,
        markdown: @markdown,
        sites: Jason.encode!(for site <- SiteTools.sites(), do: [site, SiteTools.name(site)])
      )

    ~H"""
    <Regent.Structure.dialog
      id={@id}
      class="code-card agent-tools"
      aria-labelledby={"#{@id}-title"}
      data-agent-tools
      phx-update="ignore"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes(["open", "data-settled"])}
    >
      <header class="code-card__head">
        <h2 id={"#{@id}-title"}>{@label}</h2>
        <div class="code-card__copy">
          <Regent.Primitives.copy_button id={"#{@id}-copy"} text={@markdown}>
            Copy as Markdown
          </Regent.Primitives.copy_button>
          <div class="agent-tools__every-site" data-agent-tools-sites={@sites}>
            <Regent.Primitives.copy_button
              id={"#{@id}-copy-all"}
              target={"#{@id}-all"}
              data-agent-tools-copy-all
              {%{"disabled" => true}}
            >
              Copy all Regents WebMCP tools
            </Regent.Primitives.copy_button>
            <p class="agent-tools__note" data-agent-tools-note>Reading every site's tools…</p>
            <pre id={"#{@id}-all"} hidden data-agent-tools-all></pre>
          </div>
        </div>
        <button type="button" class="code-card__close" aria-label="Close" data-agent-tools-close>
          <svg viewBox="0 0 16 16" aria-hidden="true">
            <path d="M3 3l10 10M13 3L3 13" fill="none" stroke="currentColor" stroke-width="1.5" />
          </svg>
        </button>
      </header>
      <div class="code-card__body">
        <ol class="code-card__list">
          <li :for={tool <- @tools} class="code-card__tool">
            <h3>{tool.title}</h3>
            <code>{tool.name}</code>
            <p>{tool.description}</p>
          </li>
        </ol>
      </div>
    </Regent.Structure.dialog>
    """
  end
end

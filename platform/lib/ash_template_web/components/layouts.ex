defmodule AshTemplateWeb.Layouts do
  @moduledoc "Root document layout for the public page and persistent shell."

  use AshTemplateWeb, :html

  embed_templates("layouts/*")

  attr :flash, :map, required: true
  attr :inner_content, :any, required: true

  def app(assigns) do
    ~H"""
    {@inner_content}
    <div id="flash-region" aria-live="polite">
      <Regent.Primitives.notice
        :for={tone <- ~w(info error)a}
        :if={message = Phoenix.Flash.get(@flash, tone)}
        tone={Atom.to_string(tone)}
      >
        {message}
      </Regent.Primitives.notice>
    </div>
    """
  end

  # REGENT on Base, the token every Regent site names in its footer.
  @buy_regent "https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"

  attr :theme_toggle, :boolean,
    default: true,
    doc: "false on the home page, which is always dark"

  @doc """
  The footer of the home page and every public page, the same on every Regent site:
  the social links, Buy $REGENT, the site's documents and its two plain-text guides
  for agents, which open in the browser's popover from "Agent guide". Below a public
  page it sits at the foot of the screen however short the page is.
  """
  def product_links(assigns) do
    assigns = assign(assigns, :buy_regent, @buy_regent)

    ~H"""
    <footer class="regent-footer">
      <div class="regent-footer__social">
        <AshTemplateWeb.Components.RegentLinks.header_links id="footer-brand-links" />
        <AshTemplateWeb.Components.Shell.theme_toggle
          :if={@theme_toggle}
          id="footer-theme-control"
        />
      </div>
      <nav class="regent-footer__links" aria-label="About Ash Template">
        <a href={@buy_regent} target="_blank" rel="noopener noreferrer">Buy $REGENT</a>
        <a href={~p"/about"}>About</a>
        <a href={~p"/docs"}>Developer docs</a>
        <span class="rg-tip">
          <button type="button" class="regent-footer__guide" popovertarget="footer-agent-guide">
            Agent guide
          </button>
          <div id="footer-agent-guide" class="rg-tip-body regent-footer__guide-body" popover>
            <p>Give your agent one of these.</p>
            <a href={~p"/agents.md"}>Setup steps</a>
            <a href={~p"/llms.txt"}>Site summary</a>
          </div>
        </span>
        <a href={~p"/contact"}>Contact</a>
        <span class="regent-footer__legal">
          <a href={~p"/privacy"}>Privacy policy</a>
          <a href={~p"/terms"}>Terms of use</a>
        </span>
      </nav>
      <p>© 2026 Regents Labs</p>
    </footer>
    """
  end
end

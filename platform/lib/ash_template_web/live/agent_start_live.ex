defmodule AshTemplateWeb.AgentStartLive do
  @moduledoc """
  The `/start` page: how a person connects their agent, one tab per agent. It
  reads nothing and answers no events, so it stays open while the site is closed,
  in the reading frame the documentation pages use.
  """
  use AshTemplateWeb, :live_view

  import AshTemplateWeb.Components.PageHead

  alias AshTemplateWeb.{AgentStart, PublicDocuments}
  alias AshTemplateWeb.Components.InformationNavigation

  def mount(_params, _session, socket),
    do:
      {:ok,
       socket |> assign(PublicDocuments.page("/start")) |> assign(agents: AgentStart.agents())}

  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, agent: AgentStart.agent(params["agent"]))}

  def render(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame public-document">
      <InformationNavigation.header current_path="/start" />
      <main class="legal-page">
        <article id="agent-start-page" class="account-page agent-start">
          <.page_head title="Connect your agent">
            <:tip>
              It works for you on your notes and rooms and reads your Credits and Points. It can't use your wallet or change your account.
            </:tip>
          </.page_head>

          <section class="account-panel agent-start__handoff" aria-labelledby="agent-start-give">
            <nav class="agent-start__tabs" aria-label="Which agent?">
              <.link
                :for={agent <- @agents}
                patch={~p"/start?#{[agent: agent.id]}"}
                aria-current={if agent.id == @agent.id, do: "page"}
              >{agent.label}</.link>
            </nav>
            <div class="agent-start__head">
              <label id="agent-start-give" for="agent-start-text">Give this to your agent</label>
              <Regent.Primitives.copy_button
                id="agent-start-copy"
                target="agent-start-text"
                aria-label={"Copy the steps for #{@agent.label}"}
              >Copy</Regent.Primitives.copy_button>
            </div>
            <textarea id="agent-start-text" readonly rows="16">{AgentStart.instruction(@agent)}</textarea>
          </section>

          <section class="account-panel" aria-labelledby="agent-start-steps-title">
            <h2 id="agent-start-steps-title">What happens</h2>
            <ol class="agent-start__steps">
              <li>
                <h3>Make a code</h3>
                <p>
                  Sign in, then open Pair New Agent in the side panel and choose your agent. The code works once, for ten minutes.
                </p>
                <.link href={"#{~p"/account"}#shell-pairing"}>Pair New Agent</.link>
              </li>
              <li>
                <h3>Your agent pairs</h3>
                <p>It shows in your side panel under its name.</p>
              </li>
              <li>
                <h3>It works for you</h3>
                <p>Your notes and rooms, and your Credits and Points.</p>
              </li>
              <li>
                <h3>It asks first</h3>
                <p>Before it posts, pins a note or deletes anything.</p>
              </li>
            </ol>
          </section>
        </article>
      </main>
    </div>
    """
  end
end

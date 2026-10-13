defmodule AshTemplateWeb.AgentStartLive do
  @moduledoc "The `/start` page: how a person connects their agent, one tab per agent."
  use AshTemplateWeb, :html

  import AshTemplateWeb.Components.PageHead

  alias AshTemplateWeb.AgentStart

  attr :agent, :string, default: nil, doc: "the chosen agent's id from `?agent=`"

  def page(assigns) do
    assigns = assign(assigns, agent: AgentStart.agent(assigns.agent), agents: AgentStart.agents())

    ~H"""
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
            <p>On your Account page, choose your agent. The code works once, for ten minutes.</p>
            <.link navigate={~p"/account"}>Open Account</.link>
          </li>
          <li>
            <h3>Your agent pairs</h3>
            <p>It shows on your Account page under its name.</p>
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
    """
  end
end

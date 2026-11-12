defmodule AshTemplateWeb.Components.Reading do
  @moduledoc """
  The reading view: every reading page opens inside the shell with it (`/agents`,
  each agent's page, `/docs`, `/changelog`, `/about`, `/privacy`, `/terms` and
  `/skills`), drawn from the same committed Markdown its twin serves to agents
  (`AshTemplateWeb.PublicDocuments`). The document's own title is the page's
  title row, and the rest of it follows as prose. `/agents` also holds the Agent
  Message button and its dialog.
  """

  use Phoenix.Component

  import AshTemplateWeb.Components.PageHead

  alias AshTemplateWeb.Components.AgentMessage
  alias AshTemplateWeb.PublicDocuments

  @pages [:agents, :agent, :docs, :changelog, :about, :privacy, :terms, :skills]

  @doc "The live actions that open a reading page."
  def pages, do: @pages

  attr :path, :string, required: true, doc: "the page's address"
  attr :account, :map, default: nil, doc: "the signed-in account, or nil"
  attr :lease, :map, default: nil, doc: "the page's `session_lease`"
  attr :client_key, :string, default: nil, doc: "the page's `client_key`"

  def page(assigns) do
    "# " <> document = markdown(assigns.path)
    [title, prose] = String.split(document, "\n", parts: 2)
    assigns = assign(assigns, title: title, prose: prose, message?: assigns.path == "/agents")

    ~H"""
    <article id="reading" class="reading" aria-labelledby="page-title">
      <.page_head title={@title}>
        <:actions :if={@message?}>
          <AgentMessage.button id="agents-message-button" dialog="agents-message" />
        </:actions>
      </.page_head>
      <div class="reading__prose">{PublicDocuments.html(@prose)}</div>
      <AgentMessage.dialog
        :if={@message?}
        id="agents-message"
        topic="agents"
        account={@account}
        lease={@lease}
        client_key={@client_key}
      />
    </article>
    """
  end

  defp markdown("/skills"), do: PublicDocuments.skills()
  defp markdown(path), do: PublicDocuments.document(path).markdown
end

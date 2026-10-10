defmodule AshTemplateWeb.LegalController do
  @moduledoc "Serves the public Privacy Policy and Terms of Use."
  use AshTemplateWeb, :controller

  def privacy(conn, _params), do: show(conn, :privacy)
  def terms(conn, _params), do: show(conn, :terms)

  defp show(conn, id) do
    page = AshTemplateWeb.PublicDocuments.page(conn.request_path)
    render(conn, :show, [document: AshTemplate.Legal.document(id)] ++ page)
  end
end

defmodule AshTemplateWeb.LegalHTML do
  @moduledoc false
  use AshTemplateWeb, :html

  def show(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame public-document">
      <AshTemplateWeb.Components.InformationNavigation.header current_path={@conn.request_path} />
      <main class="legal-page">
        {@document.html}
      </main>
    </div>
    """
  end
end

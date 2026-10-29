defmodule AshTemplateWeb.TooManyPagesController do
  @moduledoc "The page a live page past its address's limit is sent to (`AshTemplateWeb.Live.OpenPages`)."
  use AshTemplateWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:too_many_requests)
    |> put_resp_header("cache-control", "no-store")
    |> render(:show, AshTemplateWeb.PublicDocuments.page(:too_many_pages))
  end
end

defmodule AshTemplateWeb.TooManyPagesHTML do
  @moduledoc false
  use AshTemplateWeb, :html

  def show(assigns) do
    ~H"""
    <Regent.Structure.frame class="rl-root">
      <main class="rl-hero rg-inset">
        <div class="rl-hero-copy">
          <p class="rl-overline">Ash Template</p>
          <h1 class="rg-hero-title">Limit reached</h1>
          <p>This connection has too many pages open. Close one and try again.</p>
          <div class="rl-hero-actions">
            <a href={~p"/"} class="rg-button"><span class="rg-button__label">Go to the homepage</span></a>
          </div>
        </div>
      </main>
    </Regent.Structure.frame>
    """
  end
end

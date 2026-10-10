defmodule AshTemplateWeb.PublicPagesController do
  @moduledoc "Public documentation and discovery; no account or database reads."
  use AshTemplateWeb, :controller
  alias AshTemplateWeb.{AgentSkills, PublicDocuments}

  def show(conn, _params), do: show_document(conn, PublicDocuments.document(conn.request_path))

  def skills(conn, _params), do: show_document(conn, PublicDocuments.skills_page())

  def developers(conn, _params), do: conn |> put_status(301) |> redirect(to: "/docs")

  def agents(conn, _params), do: send_cached(conn, "text/markdown", PublicDocuments.agents())

  def build_skill(conn, _params),
    do: send_cached(conn, "text/markdown", PublicDocuments.build_skill())

  def skill_guide(conn, _params),
    do: send_cached(conn, "text/markdown", PublicDocuments.skill_guide())

  # Only the fixed table in AgentSkills answers; any other path is the site's 404.
  # The content type comes from that table too, never from the request.
  def agent_skill(conn, %{"path" => path}) do
    case AgentSkills.fetch(Enum.join(path, "/")) do
      {:ok, {type, body}} ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> send_cached(type, body, if(type == "application/zip", do: nil, else: "utf-8"))

      :error ->
        raise AshTemplateWeb.NotFoundError
    end
  end

  def openapi(conn, _params),
    do: send_cached(conn, "application/json", Jason.encode!(PublicDocuments.openapi()))

  def llms(conn, _params), do: send_cached(conn, "text/plain", PublicDocuments.llms())

  def capabilities(conn, _params),
    do: send_cached(conn, "application/json", Jason.encode!(AshTemplate.Capabilities.manifest()))

  def robots(conn, _params) do
    body = "User-agent: *\nAllow: /\n\nSitemap: #{PublicDocuments.url("/sitemap.xml")}\n"
    send_cached(conn, "text/plain", body)
  end

  def security(conn, _params), do: send_cached(conn, "text/plain", PublicDocuments.security_txt())

  # The body is JSON built from this site's own addresses, sent as a linkset with
  # the RFC 9727 profile.
  def api_catalog(conn, _params) do
    type = ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")
    send_cached(conn, type, Jason.encode!(PublicDocuments.api_catalog()), nil)
  end

  def sitemap(conn, _params),
    do:
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, PublicDocuments.sitemap())

  defp show_document(conn, document),
    do: render(conn, :show, [document: document] ++ PublicDocuments.page(conn.request_path))

  # These documents change only with a release: a sha256 ETag of the body and a
  # five-minute public cache, as Keyfleet sends on its agent files. Every type
  # and body comes from this site's own tables, never from the request.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp send_cached(conn, type, body, charset \\ "utf-8") do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_content_type(type, charset)
    |> send_resp(200, body)
  end
end

defmodule AshTemplateWeb.PublicPagesHTML do
  @moduledoc false
  use AshTemplateWeb, :html

  def show(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame public-document">
      <AshTemplateWeb.Components.InformationNavigation.header current_path={@conn.request_path} />
      <main class="legal-page">
        {AshTemplateWeb.PublicDocuments.html(@document.markdown)}
      </main>
    </div>
    """
  end
end

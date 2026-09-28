defmodule AshTemplateWeb.PublicPagesController do
  @moduledoc "Public documentation and discovery; no account or database reads."
  use AshTemplateWeb, :controller
  alias AshTemplateWeb.{AgentSkills, PublicDocuments}

  def show(conn, _params) do
    document = PublicDocuments.document(conn.request_path)
    render(conn, :show, [document: document] ++ PublicDocuments.page(conn.request_path))
  end

  def developers(conn, _params), do: conn |> put_status(301) |> redirect(to: "/docs")

  def skills(conn, _params) do
    render(
      conn,
      :show,
      [document: PublicDocuments.skills_page()] ++ PublicDocuments.page("/skills")
    )
  end

  def skill_guide(conn, _params) do
    body = PublicDocuments.skill_guide()
    conn |> cached(body) |> put_resp_content_type("text/markdown") |> send_resp(200, body)
  end

  # Only the fixed table in AgentSkills answers; any other path is the site's 404.
  # The content type comes from that table too, never from the request.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  def agent_skill(conn, %{"path" => path}) do
    case AgentSkills.fetch(Enum.join(path, "/")) do
      {:ok, {type, body}} ->
        conn
        |> cached(body)
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_content_type(type, if(type == "application/zip", do: nil, else: "utf-8"))
        |> send_resp(200, body)

      :error ->
        raise AshTemplateWeb.NotFoundError
    end
  end

  def openapi(conn, _params) do
    body = Jason.encode!(PublicDocuments.openapi())
    conn |> cached(body) |> put_resp_content_type("application/json") |> send_resp(200, body)
  end

  def llms(conn, _params) do
    body = PublicDocuments.llms()
    conn |> cached(body) |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  def capabilities(conn, _params) do
    body = Jason.encode!(AshTemplate.Capabilities.manifest())
    conn |> cached(body) |> put_resp_content_type("application/json") |> send_resp(200, body)
  end

  def robots(conn, _params) do
    body = "User-agent: *\nAllow: /\n\nSitemap: #{PublicDocuments.url("/sitemap.xml")}\n"
    conn |> cached(body) |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  def security(conn, _params) do
    body = PublicDocuments.security_txt()
    conn |> cached(body) |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  # The body is JSON built from this site's own addresses, sent as a linkset with
  # the RFC 9727 profile, which Sobelow does not read as a safe content type.
  # sobelow_skip ["XSS.SendResp"]
  def api_catalog(conn, _params) do
    body = Jason.encode!(PublicDocuments.api_catalog())

    conn
    |> cached(body)
    |> put_resp_content_type(
      ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727"),
      nil
    )
    |> send_resp(200, body)
  end

  def sitemap(conn, _params),
    do:
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, PublicDocuments.sitemap())

  # These documents change only with a release: a sha256 ETag of the body and a
  # five-minute public cache, as KeyFleet sends on its agent files.
  defp cached(conn, body) do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
  end
end

defmodule AshTemplateWeb.PublicPagesHTML do
  @moduledoc false
  use AshTemplateWeb, :html

  def show(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame public-document">
      <header class="legal-header">
        <a href={~p"/"} class="legal-home">Ash Template</a>
        <nav class="legal-nav" aria-label="Information">
          <a
            :for={{label, path} <- [{"Docs", "/docs"}, {"About", "/about"}, {"Contact", "/contact"}]}
            href={path}
            aria-current={if(@conn.request_path == path, do: "page")}
          >
            {label}
          </a>
        </nav>
      </header>
      <main class="legal-page">
        {AshTemplateWeb.PublicDocuments.html(@document.markdown)}
      </main>
    </div>
    """
  end
end

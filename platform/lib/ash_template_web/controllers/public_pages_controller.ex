defmodule AshTemplateWeb.PublicPagesController do
  @moduledoc "Public documentation and discovery; no account or database reads."
  use AshTemplateWeb, :controller
  alias AshTemplateWeb.{AgentGuides, AgentSkills, Capabilities, PublicDocuments}

  # The served HTTP contract, copied from contracts/ by `mix ash_template.sync_api_contract`.
  # Its major version and digest go out in two headers, both read from the file
  # itself, so a change to the contract moves them together.
  @contract_file Application.app_dir(:ash_template, "priv/static/api-contract.openapiv3.yaml")
  @external_resource @contract_file
  @contract File.read!(@contract_file)
  [_, contract_major] = Regex.run(~r/^  version:\s*(\d+)\./m, @contract)
  @contract_major contract_major
  @contract_digest "sha256:" <> Base.encode16(:crypto.hash(:sha256, @contract), case: :lower)

  def show(conn, _params) do
    case PublicDocuments.document(conn.request_path) do
      nil -> raise AshTemplateWeb.NotFoundError
      document -> show_document(conn, document)
    end
  end

  def skills(conn, _params), do: show_document(conn, PublicDocuments.skills_page())

  @doc "A public page as JSON, `{title, markdown}`: the `about` and `docs` tools and commands."
  def document(conn, _params) do
    %{title: title, markdown: markdown} = PublicDocuments.document(conn.assigns.document)
    send_cached(conn, "application/json", Jason.encode!(%{title: title, markdown: markdown}))
  end

  def agents(conn, _params), do: send_cached(conn, "text/markdown", PublicDocuments.agents())

  def build_skill(conn, _params),
    do: send_cached(conn, "text/markdown", PublicDocuments.build_skill())

  def skill_guide(conn, _params),
    do: send_cached(conn, "text/markdown", PublicDocuments.skill_guide())

  @doc "One agent's skill: the agent guide with that agent's Set up section added."
  def agent_skill_guide(conn, %{"agent" => slug}) do
    case AgentGuides.skill(slug) do
      nil -> raise AshTemplateWeb.NotFoundError
      skill -> send_cached(conn, "text/markdown", skill)
    end
  end

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

  def api_contract(conn, _params) do
    conn
    |> put_resp_header("x-regents-contract-major", @contract_major)
    |> put_resp_header("x-regents-contract-digest", @contract_digest)
    |> send_cached("application/yaml", @contract)
  end

  def llms(conn, _params), do: send_cached(conn, "text/plain", PublicDocuments.llms())

  def capabilities(conn, _params),
    do: send_cached(conn, "application/json", Jason.encode!(Capabilities.document()))

  def robots(conn, _params) do
    body = "User-agent: *\nAllow: /\n\nSitemap: #{PublicDocuments.url("/sitemap.xml")}\n"
    send_cached(conn, "text/plain", body)
  end

  def security(conn, _params), do: send_cached(conn, "text/plain", PublicDocuments.security_txt())

  # The IndexNow key, which proves the pages this site sends came from it
  # (AshTemplate.IndexNow); not found while no key is set.
  def indexnow_key(conn, _params) do
    case AshTemplate.IndexNow.key() do
      nil -> raise AshTemplateWeb.NotFoundError
      key -> send_cached(conn, "text/plain", key)
    end
  end

  # The body is JSON built from this site's own addresses, sent as a linkset with
  # the RFC 9727 profile.
  def api_catalog(conn, _params) do
    type = ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")
    send_cached(conn, type, Jason.encode!(PublicDocuments.api_catalog()), nil)
  end

  # XML from fixed page paths; PublicDocuments.sitemap/0 escapes every location.
  def sitemap(conn, _params), do: send_cached(conn, "application/xml", PublicDocuments.sitemap())

  defp show_document(conn, document),
    do: render(conn, :show, [document: document] ++ PublicDocuments.page(conn.request_path))

  # Every public document and agent file is sent here. Each changes only with a
  # release and is the same for everyone who asks, so it carries a sha256 ETag of
  # its body and a five-minute public cache, and a caller that already holds this
  # body gets 304 with no body. Like a static file, it is never a page: it carries
  # the endpoint's static headers. Nothing that varies by the signed-in person is sent
  # this way. Every type and body comes from this site's own tables, never from the
  # request.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp send_cached(conn, type, body, charset \\ "utf-8") do
    etag = ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}")

    conn =
      conn
      |> put_resp_header("etag", etag)
      |> put_resp_header("cache-control", "public, max-age=300")
      |> merge_resp_headers(AshTemplateWeb.Endpoint.static_headers())

    if held?(conn, etag),
      do: send_resp(conn, 304, ""),
      else: conn |> put_resp_content_type(type, charset) |> send_resp(200, body)
  end

  # If-None-Match lists one or more tags, or `*`, and compares them weakly (RFC 9110),
  # so `W/"<tag>"` from a cache that compressed the body matches too.
  defp held?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.any?(&(String.trim(&1) in ["*", etag, "W/" <> etag]))
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

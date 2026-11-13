defmodule AshTemplate.LaunchGateTest do
  # Invariant: closing the site never closes the reading pages, the agent's guide
  # first among them. Changes the site-wide gate, so it never runs beside another test.
  use ExUnit.Case, async: false
  import Plug.Test

  alias AshTemplateWeb.PublicDocuments

  @reading ~w(/agents /agents/dots /docs /changelog /about /privacy /terms)

  setup do
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    on_exit(fn -> Application.put_env(:ash_template, :app_surfaces, open?) end)
    Application.put_env(:ash_template, :app_surfaces, false)
  end

  # From this machine, where the build skills answer too (AshTemplateWeb.Showcase).
  defp request(path),
    do: :get |> conn("http://localhost" <> path) |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))

  test "the reading pages stay open, inside the shell, while the rest of the site is closed" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AshTemplate.Repo)

    for path <- ["/skills" | @reading] do
      assert %{status: 200, resp_body: body} = request(path)
      page = LazyHTML.from_document(body)
      assert Enum.count(LazyHTML.query(page, "#app-shell #route-content .reading__prose")) == 1
      assert Enum.count(LazyHTML.query(page, "#shell-footer")) == 1
    end

    # Each is headed by its document's title; the developer documentation by Docs.
    for path <- @reading do
      "# " <> document = PublicDocuments.document(path).markdown
      [title | _prose] = String.split(document, "\n", parts: 2)
      heading = request(path).resp_body |> LazyHTML.from_document() |> LazyHTML.query("#route-content h1")
      assert LazyHTML.text(heading) == if(path == "/docs", do: "Docs", else: title)
    end

    # The gate really was closed for these requests.
    assert %{status: 503} = closed = request("/account")
    assert Plug.Conn.get_resp_header(closed, "retry-after") == ["3600"]
  end

  test "the health read and the documents' JSON stay open while the site is closed" do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(AshTemplate.Repo)

    assert %{status: 200} = request("/api/v1/health")
    assert %{status: 200, resp_body: docs} = request("/api/v1/docs")
    assert %{"title" => _, "markdown" => _} = Jason.decode!(docs)
    assert %{status: 200} = request("/api/v1/about")

    # The rest of the API is closed with the site.
    assert %{status: 503} = request("/api/v1/rooms")
  end

  test "the MCP address says it is not open yet in JSON, whatever its caller accepts" do
    closed =
      :get
      |> conn("/mcp")
      |> Plug.Conn.put_req_header("accept", "text/event-stream")
      |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))

    assert closed.status == 503
    assert %{"error" => %{"code" => "not_open_yet"}} = Jason.decode!(closed.resp_body)
  end
end

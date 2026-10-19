defmodule AshTemplateWeb.StaticCacheTest do
  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test, only: [conn: 2]

  @chunks Application.app_dir(:ash_template, "priv/static/assets/js/chunks")

  # Regression: esbuild's shared script pieces were sent with "public" alone, so
  # every return visit asked for each one again. Their names change with their
  # contents, so a browser may keep them for a year.
  test "a script piece named by its contents is kept for a year" do
    created? = not File.dir?(@chunks)
    File.mkdir_p!(@chunks)
    piece = Path.join(@chunks, "speed-check-#{System.unique_integer([:positive])}.js")
    File.write!(piece, "export const piece = 1\n")

    on_exit(fn ->
      File.rm!(piece)
      if created?, do: File.rmdir!(@chunks)
    end)

    response = request("/assets/js/chunks/" <> Path.basename(piece))

    assert response.status == 200
    assert get_resp_header(response, "cache-control") == ["public, max-age=31536000, immutable"]
  end

  # Regression: the sitemap was the one public document sent as private, so no
  # shared cache could keep it.
  test "the sitemap is a shared document like the other public ones" do
    response = request("/sitemap.xml")

    assert response.status == 200
    assert get_resp_header(response, "cache-control") == ["public, max-age=300"]
    assert [_etag] = get_resp_header(response, "etag")
  end

  defp request(path) do
    :get
    |> conn(path)
    |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))
  end
end

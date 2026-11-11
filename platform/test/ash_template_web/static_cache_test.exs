defmodule AshTemplateWeb.StaticCacheTest do
  use ExUnit.Case, async: false

  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test, only: [conn: 2]

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

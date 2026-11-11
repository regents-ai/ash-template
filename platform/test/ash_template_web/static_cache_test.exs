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

  test "a caller that holds a public document's body gets 304 and no body" do
    [etag] = get_resp_header(request("/llms.txt"), "etag")

    for held <- [etag, "W/" <> etag, ~s("other", #{etag}), "*"] do
      response = request("/llms.txt", [{"if-none-match", held}])

      assert response.status == 304, held
      assert response.resp_body == ""
      assert get_resp_header(response, "etag") == [etag]
    end

    assert request("/llms.txt", [{"if-none-match", ~s("other")}]).status == 200
  end

  # The product CLI reads the contract's major version and digest from these
  # headers before it changes anything.
  test "the contract carries its major version and digest, and is never a page" do
    response = request("/api-contract.openapiv3.yaml")
    body = response.resp_body

    assert response.status == 200
    assert [type] = get_resp_header(response, "content-type")
    assert type =~ "application/yaml"
    [_, major] = Regex.run(~r/^  version:\s*(\d+)\./m, body)
    assert get_resp_header(response, "x-regents-contract-major") == [major]

    assert get_resp_header(response, "x-regents-contract-digest") ==
             ["sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)]

    for {name, value} <- AshTemplateWeb.Endpoint.static_headers() do
      assert get_resp_header(response, name) == [value]
    end
  end

  defp request(path, headers \\ []) do
    headers
    |> Enum.reduce(conn(:get, path), fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
    |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))
  end
end

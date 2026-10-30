defmodule AshTemplateWeb.NoSniffingTest do
  # Every answer the site gives tells the browser to read it only as the type it
  # names: a page, a file, a redirect, the hosted MCP server's answers and every
  # refusal, whether a page or JSON.
  use ExUnit.Case, async: false

  import Plug.Conn, only: [put_req_header: 3]
  import Plug.Test, only: [conn: 2, conn: 3]

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    Application.put_env(:ash_template, :app_surfaces, true)
    on_exit(fn -> Application.put_env(:ash_template, :app_surfaces, open?) end)
  end

  test "pages, files, redirects, the MCP server's answers and refusals" do
    for {conn, status} <- [
          {conn(:get, "/"), 200},
          {conn(:get, "/favicon.svg"), 200},
          {conn(:get, "http://www.#{@endpoint.host()}/notes"), 301},
          {conn(:post, "/mcp", "{}") |> put_req_header("content-type", "application/json"), 401},
          {conn(:get, "/") |> put_req_header("accept", "application/json"), 406},
          {conn(:get, "/?_format=json") |> put_req_header("accept", "text/html"), 406},
          {conn(:get, "/no-such-page"), 404},
          {conn(:get, "/api/v1/no-such-thing"), 404},
          {conn(:post, "/visit-log", String.duplicate("a", 262_145))
           |> put_req_header("content-type", "application/x-www-form-urlencoded"), 413}
        ] do
      assert {^status, headers} = answer(from(conn))
      assert {"x-content-type-options", "nosniff"} in headers
    end
  end

  # The answer as sent, whether the request was answered or raised on the way.
  defp answer(conn) do
    discard_sent()
    response = @endpoint.call(conn, [])
    {response.status, response.resp_headers}
  rescue
    error ->
      receive do
        {ref, {status, headers, _body}} when is_reference(ref) -> {status, headers}
      after
        0 -> flunk("#{conn.request_path} raised #{inspect(error.__struct__)} and sent nothing")
      end
  end

  # Each answer also leaves {:plug_conn, :sent}, which tells Phoenix the next request
  # was already answered and skips its refusal page.
  defp discard_sent do
    receive do
      {ref, {_status, _headers, _body}} when is_reference(ref) -> discard_sent()
      {:plug_conn, :sent} -> discard_sent()
    after
      0 -> :ok
    end
  end

  defp from(conn),
    do: Map.put(conn, :remote_ip, {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)})
end

defmodule AshTemplateWeb.BodyLimitTest do
  # Every address that takes a body reads it up to its limit and refuses one byte
  # more with 413, before anything acts on it: 64 KB for what an agent signs (the
  # API, the hosted MCP server and Stripe's notices, all under /api or /mcp), 256 KB
  # for everything else (a connected app's registration and token, sign-in, the
  # browser's visit reports). A body of any other type is never read here, and no
  # page takes a file.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  @endpoint AshTemplateWeb.Endpoint

  @signed 65_536
  @unsigned 262_144

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
  end

  for {path, limit, type} <- [
        {"/mcp", @signed, :json},
        {"/api/v1/notes", @signed, :json},
        {"/api/stripe/notices", @signed, :json},
        {"/oauth/register", @unsigned, :json},
        {"/oauth/token", @unsigned, :form},
        {"/auth/privy/session", @unsigned, :json},
        {"/visit-log", @unsigned, :json}
      ] do
    test "POST #{path} reads #{limit} bytes and refuses one more" do
      assert answer(unquote(path), unquote(type), unquote(limit)) != 413
      assert answer(unquote(path), unquote(type), unquote(limit) + 1) == 413
    end
  end

  # A body of exactly `size` bytes, padded inside one field.
  defp answer(path, type, size) do
    {content_type, body} = body(type, size)
    assert byte_size(body) == size

    conn =
      conn(:post, path, body)
      |> Map.put(:remote_ip, {10, :rand.uniform(250), :rand.uniform(250), :rand.uniform(250)})
      |> put_req_header("content-type", content_type)

    discard_sent()

    try do
      @endpoint.call(conn, []).status
    rescue
      _error -> conn |> sent_resp() |> elem(0)
    end
  end

  # An earlier answer leaves {:plug_conn, :sent}, which tells Phoenix the next request
  # was already answered and skips its refusal page.
  defp discard_sent do
    receive do
      {:plug_conn, :sent} -> discard_sent()
    after
      0 -> :ok
    end
  end

  defp body(:json, size),
    do: {"application/json", ~s({"padding":"#{String.duplicate("a", size - 14)}"})}

  defp body(:form, size),
    do: {"application/x-www-form-urlencoded", "padding=" <> String.duplicate("a", size - 8)}
end

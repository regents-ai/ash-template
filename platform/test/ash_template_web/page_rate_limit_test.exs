defmodule AshTemplateWeb.PageRateLimitTest do
  # Invariant: each page load renders the page and runs its reads, so one
  # address loads at most 600 pages or documents a minute; another address is
  # still served.
  use ExUnit.Case, async: true
  import Plug.Test

  defp load(from) do
    conn(:get, "/llms.txt")
    |> Map.put(:remote_ip, from)
    |> AshTemplateWeb.Endpoint.call([])
  end

  test "one address loads 600 pages a minute; the next waits, and another address does not" do
    from = {198, 51, 100, 77}

    statuses = for _ <- 1..600, do: load(from).status
    assert Enum.uniq(statuses) == [200]

    waited = load(from)
    assert waited.status == 429
    assert [_seconds] = Plug.Conn.get_resp_header(waited, "retry-after")

    assert load({198, 51, 100, 78}).status == 200
  end
end

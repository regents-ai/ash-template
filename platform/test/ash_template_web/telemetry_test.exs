defmodule AshTemplateWeb.TelemetryTest do
  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 2]

  alias AshTemplate.Repo
  alias Ecto.Adapters.SQL.Sandbox

  # Every site's dashboard reads request and query time by these names, so a
  # request and a query must each land in the scrape.
  test "a request is timed by its route pattern and a query by its whole time" do
    :ok = Sandbox.checkout(Repo)

    :get |> conn("/sitemap.xml") |> AshTemplateWeb.Endpoint.call(AshTemplateWeb.Endpoint.init([]))
    Repo.query!("SELECT 1")

    scrape = AshTemplateWeb.Telemetry.scrape()

    assert scrape =~ ~r/^ash_template_request_duration_microseconds_count\{route="\/sitemap.xml"\} [1-9]/m
    assert scrape =~ ~r/^ash_template_repo_query_microseconds_count [1-9]/m
  end
end

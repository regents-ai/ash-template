defmodule AshTemplateWeb.HomeLiveTest do
  # The homepage tracks regents.sh's; what it shows and how its two columns sit is
  # checked in the browser (test/browser/homepage.spec.ts). Here: an agent reading
  # the page's Markdown reads it in the order a visitor does.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias AshTemplateWeb.HomeLive

  @endpoint AshTemplateWeb.Endpoint

  test "the page and its agent copy read in the same order" do
    html = build_conn() |> get("/") |> html_response(200)

    panels =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-home-panel]")
      |> LazyHTML.attribute("data-home-panel")

    assert panels == ~w(hero mission products staking how)

    assert Regex.scan(~r/^## (.+)$/m, HomeLive.agent_markdown(), capture: :all_but_first) == [
             ["A starting point for your next product"],
             ["Mission"],
             ["Products"],
             ["Staking"],
             ["How it works"]
           ]
  end
end

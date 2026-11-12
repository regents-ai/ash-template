defmodule AshTemplateWeb.ValueCardsLiveTest do
  # The value cards in the motion lab: every card the page shows has a still frame
  # to stand in for its moving panel. That every panel has a still frame, and the
  # rules of the one device the panels share, are in assets/test/value_cards.test.ts.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [build_conn: 0, get: 2, html_response: 2]

  @endpoint AshTemplateWeb.Endpoint

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    open? = Application.fetch_env!(:ash_template, :app_surfaces)
    Application.put_env(:ash_template, :app_surfaces, true)

    on_exit(fn ->
      Application.put_env(:ash_template, :app_surfaces, open?)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "every card on the page has its still frame" do
    stills =
      build_conn()
      |> get("/animations/value-cards")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("img.value-card__still")
      |> LazyHTML.attribute("src")

    assert stills != []

    for src <- stills do
      path = URI.parse(src).path
      still = Application.app_dir(:ash_template, Path.join("priv/static", path))
      assert File.exists?(still), "no still frame at #{path}"
    end
  end
end

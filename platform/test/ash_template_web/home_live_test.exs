defmodule AshTemplateWeb.HomeLiveTest do
  # The homepage tracks regents.sh's: the datascape behind one glass panel. How the
  # panel sits over the picture is checked in the browser
  # (test/browser/homepage.spec.ts). Here: what the server renders, and that an
  # agent reading the page's Markdown reads it in the order a visitor does.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias AshTemplateWeb.HomeLive

  @endpoint AshTemplateWeb.Endpoint

  @line "We build tools for people and their agents. REGENT stakers share in the revenue."

  setup do
    %{html: build_conn() |> get("/") |> html_response(200)}
  end

  test "the product tabs open their sites; Protocol opens staking; Enter App opens the app", %{
    html: html
  } do
    assert attribute(html, "#home-glass nav.home__foot a", "href") ==
             ~w(https://autolaunch.sh https://techtree.sh https://patchbay.help https://keyfleet.ai https://regents.sh/stake)

    assert attribute(html, "#home-content a.rl-hero-cta", "href") == ["/app"]
  end

  test "the page and its agent copy read in the same order", %{html: html} do
    order =
      ["Ash Template", @line, "Enter App", "WebMCP Tools"] ++
        ["Connect your agent from the command line"] ++
        ["Products"] ++ ~w(Autolaunch Techtree Patchbay Keyfleet Protocol)

    assert in_order?(text(html, "#home-glass"), order)
    assert in_order?(HomeLive.agent_markdown(), order ++ ["© 2026 Regents Labs"])

    assert Regex.scan(~r/^## (.+)$/m, HomeLive.agent_markdown(), capture: :all_but_first) ==
             [[text(html, "#home-glass .home__foot h2")]]
  end

  test "the panel's foot is the products alone, and the copyright stands outside it", %{
    html: html
  } do
    assert attribute(html, "#home-glass .home__foot", "aria-labelledby") == ["home-products-title"]
    assert text(html, "#home-products-title") == "Products"

    assert attribute(html, "#home-glass .home__foot a", "id") ==
             Enum.map(~w(autolaunch techtree patchbay keyfleet protocol), &"home-nav-#{&1}")

    assert text(html, "#public-home > .home__copyright") == "© 2026 Regents Labs"
  end

  test "the name stands once, then says one plain line", %{html: html} do
    assert text(html, "h1") == "Ash Template"
    assert text(html, "#home-content .rl-statement__line") == @line
    assert HomeLive.agent_markdown() =~ ~r/\A# Ash Template\n\n#{Regex.escape(@line)}\n/
  end

  test "the picture behind the panel is decoration, hidden from assistive technology", %{
    html: html
  } do
    assert attribute(html, "#public-home img.home__still", "alt") == [""]
    assert attribute(html, "#public-home img.home__still", "aria-hidden") == ["true"]
    assert attribute(html, "#public-home canvas", "aria-hidden") == ["true"]
  end

  defp text(html, selector),
    do:
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(selector)
      |> LazyHTML.text()
      |> String.trim()

  defp in_order?(text, words) do
    Enum.reduce_while(words, 0, fn word, from ->
      case :binary.match(text, word, scope: {from, byte_size(text) - from}) do
        {at, length} -> {:cont, at + length}
        :nomatch -> {:halt, false}
      end
    end)
    |> is_integer()
  end

  defp attribute(html, selector, name),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
end

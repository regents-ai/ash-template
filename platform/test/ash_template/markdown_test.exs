defmodule AshTemplate.MarkdownTest do
  use ExUnit.Case, async: true

  test "text in braces after inline code stays in the text, with other options kept" do
    html =
      AshTemplate.Markdown.to_html!("Call `run`{limit: 3} ~~once~~.",
        extension: [strikethrough: true]
      )

    assert html =~ "{limit: 3}"
    assert html =~ "<del>once</del>"
  end
end

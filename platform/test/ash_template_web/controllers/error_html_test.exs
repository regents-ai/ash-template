defmodule AshTemplateWeb.ErrorHTMLTest do
  use AshTemplateWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(AshTemplateWeb.ErrorHTML, "404", "html", []) =~ "Not Found</h1>"
  end

  test "renders 500.html" do
    assert render_to_string(AshTemplateWeb.ErrorHTML, "500", "html", []) =~
             "Internal Server Error</h1>"
  end
end

defmodule AshTemplateWeb.ErrorHTML do
  @moduledoc "Errors on HTML requests: a headline and recovery links, in the visitor's chosen theme."
  use AshTemplateWeb, :html

  def render(template, assigns) do
    cookie = Plug.Conn.fetch_cookies(assigns.conn).req_cookies["regent_theme"]
    theme = if cookie in ["light", "dark"], do: cookie
    assigns = assign(assigns, title: headline(template), theme: theme)

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-brand="platform" data-theme={@theme}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title} · Ash Template</title>
        <link rel="stylesheet" href="/assets/js/app.css" />
      </head>
      <body>
        <Regent.Utility.page title={@title} context="Ash Template" id="error-page">
          <p>Use the homepage or one of the links below to continue.</p>
          <:actions>
            <a class="rg-button" href="/">Homepage</a>
          </:actions>
          <:note>
            <nav aria-label="Recovery links">
              <ul class="rg-utility__links">
                <li :for={{label, path} <- AshTemplateWeb.PublicDocuments.recovery_links()}>
                  <a href={path}>{label}</a>
                </li>
              </ul>
            </nav>
          </:note>
        </Regent.Utility.page>
      </body>
    </html>
    """
  end

  defp headline("404" <> _format), do: "Not found"
  defp headline(_template), do: "Error"
end

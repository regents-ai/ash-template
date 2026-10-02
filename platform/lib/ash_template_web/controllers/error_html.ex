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
        <Regent.Structure.frame>
          <Regent.Structure.row rail={false}>
            <main class="rg-inset">
              <p>Ash Template</p>
              <h1 class="rg-hero-title">{@title}</h1>
              <p><a class="rg-button rg-button--secondary" href="/">Go to the homepage</a></p>
              <nav aria-label="Recovery links">
                <ul>
                  <li :for={{label, path} <- AshTemplateWeb.PublicDocuments.recovery_links()}>
                    <a href={path}>{label}</a>
                  </li>
                </ul>
              </nav>
            </main>
          </Regent.Structure.row>
        </Regent.Structure.frame>
      </body>
    </html>
    """
  end

  defp headline("404" <> _format), do: "We can’t find that page"
  defp headline(_template), do: "Something went wrong"
end

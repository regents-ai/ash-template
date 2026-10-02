defmodule AshTemplateWeb.ErrorJSON do
  @moduledoc "Errors on JSON requests, in the site's `error: code, message, hint` shape."

  alias AshTemplateWeb.PublicDocuments

  def render(template, _assigns) do
    hint =
      "See #{PublicDocuments.url("/docs")} and #{PublicDocuments.url("/openapi.json")} for supported requests."

    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.json(hint)
  end
end

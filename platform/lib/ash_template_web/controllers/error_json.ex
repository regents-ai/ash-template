defmodule AshTemplateWeb.ErrorJSON do
  @moduledoc "Errors on JSON requests, in the site's `error: code, message, hint` shape."

  alias AshTemplateWeb.PublicDocuments

  # An address that names nothing says so, and where to find what exists.
  def render("404.json", _assigns) do
    %{
      error: %{
        code: "not_found",
        message: "There is nothing at this address.",
        hint:
          "List the rooms with GET #{PublicDocuments.url("/api/v1/rooms")}. Every endpoint is described at #{PublicDocuments.url("/openapi.json")}. Sending the same request again will not help."
      }
    }
  end

  # A body the MCP address cannot take, such as one too large, points at its own
  # section of the docs.
  def render(template, %{conn: %Plug.Conn{path_info: ["mcp" | _]}}) do
    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.json(
      "The Hosted MCP section of #{PublicDocuments.url("/docs")} says what the MCP address takes."
    )
  end

  def render(template, _assigns) do
    hint =
      "See #{PublicDocuments.url("/docs")} and #{PublicDocuments.url("/openapi.json")} for supported requests."

    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.json(hint)
  end
end

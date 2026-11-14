defmodule AshTemplateWeb.ErrorJSON do
  @moduledoc """
  Errors on JSON requests, in the site's `error: code, message, hint` shape; at
  the MCP address, the same words in a JSON-RPC error.
  """

  alias AshTemplateWeb.{McpRefusal, PublicDocuments}

  # Anything the MCP address cannot take, such as a body too large, or an
  # address under it that names nothing, points at its own section of the docs.
  def render(template, %{conn: %Plug.Conn{path_info: ["mcp" | _]} = conn} = assigns) do
    %{error: error} =
      template
      |> Phoenix.Controller.status_message_from_template()
      |> RegentAgentAccess.Recovery.json(
        "The Hosted MCP section of #{PublicDocuments.url("/docs")} says what the MCP address takes."
      )

    McpRefusal.failed(conn, assigns[:reason], error)
  end

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

  def render(template, _assigns) do
    hint =
      "See #{PublicDocuments.url("/docs")} and #{PublicDocuments.url("/openapi.json")} for supported requests."

    template
    |> Phoenix.Controller.status_message_from_template()
    |> RegentAgentAccess.Recovery.json(hint)
  end
end

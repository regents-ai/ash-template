defmodule AshTemplateWeb.Plugs.ToolInput do
  @moduledoc """
  A public read takes exactly its tool's input over HTTP: its address's named
  parts and query together are cast as the hosted tool casts them, and input
  the read does not take is refused with the code, words and status that tool
  gives the same input (`AshTemplateWeb.ToolErrors.http_refusal/2`). So the
  browser tools, which send their input as the read's address, hand on the
  same answer. Each route names its tool in its `private` `:tool`.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn

  alias AshTemplateWeb.ToolErrors

  def init(opts), do: opts

  def call(%Plug.Conn{private: %{tool: tool}} = conn, _opts) do
    case ToolErrors.http_refusal(tool, conn.params) do
      nil -> conn
      {status, body} -> conn |> put_status(status) |> json(body) |> halt()
    end
  end
end

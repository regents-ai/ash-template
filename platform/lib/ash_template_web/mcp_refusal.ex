defmodule AshTemplateWeb.McpRefusal do
  @moduledoc """
  How the hosted MCP server at `/mcp` answers a request it turns away: in
  JSON-RPC 2.0, with the request's own id, so an MCP client can match the answer
  to its call and show the model what to do next.

  A refusal keeps its HTTP status and headers (401 with `WWW-Authenticate`, 429
  with `Retry-After`, 405 with `Allow`), and its body is a JSON-RPC error:

      {"jsonrpc": "2.0", "id": 1,
       "error": {"code": -31000, "message": "...",
                 "data": {"code": "...", "message": "...", "hint": "..."}}}

  `data` is the site's own `{code, message, hint}`, with any field the refusal
  adds, such as `retry_after`. The JSON-RPC `code` is -31000 for each refusal
  the site makes, -32700 for a body that is not JSON and -32603 for a failure of
  the site's own. The id is the request's; when it could not be read (the body
  was not read yet, is not one JSON object, or is a batch) the error has none. A
  notification asks for no answer and gets the status alone, with no body.

  Once a call has run, a refusal takes the place of its answer (`replace/3`): a
  `tools/call` gets a tool result with `isError: true` at status 200, its one
  text block the refusal's `{"error": {...}}`, as the tools' own refusals are
  (`AshTemplateWeb.ToolErrors`); any other message gets the error above.
  """

  import Plug.Conn

  # Outside the codes JSON-RPC and MCP keep for themselves (-32768 to -32000).
  @refused -31_000

  @doc """
  Answers `conn` with the refusal `error`, a `{code, message, hint}` map, at
  `status`, and halts.
  """
  @spec refuse(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  def refuse(conn, status, error) do
    case refusal(message(conn), error) do
      nil ->
        conn |> send_resp(status, "") |> halt()

      answer ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(status, Jason.encode_to_iodata!(answer))
        |> halt()
    end
  end

  @doc """
  Puts the refusal `error` in place of the answer on `conn` as it leaves (a
  `register_before_send/2` callback): a `tools/call` request's becomes a tool
  result with `isError: true`.
  """
  @spec replace(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  def replace(conn, status, error) do
    {status, answer} =
      case message(conn) do
        %{"method" => "tools/call", "id" => id} when is_binary(id) or is_integer(id) ->
          {200, %{jsonrpc: "2.0", id: id, result: tool_result(error)}}

        message ->
          {status, refusal(message, error)}
      end

    {conn, body} = encode(conn, answer)
    %{conn | status: status, resp_body: body}
  end

  @doc """
  The body `AshTemplateWeb.ErrorJSON` gives at `/mcp` for an error raised around
  the server, such as a body too large or not JSON, or a failure: `error` is the
  site's `{code, message, hint}` for it, and `reason` what was raised. It has no
  id when the request's could not be read, as for a notification.
  """
  @spec failed(Plug.Conn.t(), term(), map()) :: map()
  def failed(conn, reason, error),
    do: error_body(failure_code(conn, reason), id(message(conn)), error)

  @doc "True when the request's body is JSON (`Content-Type: application/json`)."
  @spec json?(Plug.Conn.t()) :: boolean()
  def json?(conn) do
    case get_req_header(conn, "content-type") do
      [type] -> match?({:ok, "application", "json", _params}, Plug.Conn.Utils.content_type(type))
      _none_or_several -> false
    end
  end

  defp encode(conn, nil), do: {conn, ""}

  defp encode(conn, answer),
    do: {put_resp_content_type(conn, "application/json"), Jason.encode_to_iodata!(answer)}

  defp refusal(%{"method" => _} = message, _error) when not is_map_key(message, "id"), do: nil
  defp refusal(message, error), do: error_body(@refused, id(message), error)

  defp error_body(code, id, error) do
    body = %{jsonrpc: "2.0", error: %{code: code, message: error.message, data: error}}
    if is_nil(id), do: body, else: Map.put(body, :id, id)
  end

  defp tool_result(error) do
    %{
      content: [%{type: "text", text: Jason.encode!(%{error: error})}],
      isError: true,
      resultType: "complete"
    }
  end

  defp failure_code(_conn, %Plug.Parsers.ParseError{}), do: -32_700
  defp failure_code(%Plug.Conn{status: 500}, _reason), do: -32_603
  defp failure_code(_conn, _reason), do: @refused

  # The JSON-RPC message the request carries: its body, once read as JSON.
  defp message(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp message(conn), do: if(json?(conn), do: conn.body_params, else: %{})

  defp id(%{"method" => _, "id" => id}) when is_binary(id) or is_integer(id), do: id
  defp id(_message), do: nil
end

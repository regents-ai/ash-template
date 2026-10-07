defmodule AshTemplateWeb.SignedBodyReader do
  @moduledoc """
  Keeps the exact bytes of the bodies agents sign, so the sign-in service can
  check them against the request's signature (`AshTemplateWeb.Plugs.AgentWallet`,
  `RegentAgents.HTTP`): a room post or edit, a note, and a pairing. Every other
  body is read as before.
  """

  # The largest signed body is a note: 10,000 characters of text, as JSON.
  @limit 65_536

  def read_body(conn, opts) do
    if signed?(conn),
      do: read_signed(conn, opts),
      else: RegentIdentity.BodyReader.read_body(conn, opts)
  end

  defp signed?(%{method: method, path_info: path}) when method in ["POST", "PATCH"] do
    match?(["api", "v1", "rooms", _room, "messages" | _rest], path) or
      match?(["api", "v1", "notes" | _rest], path) or
      match?(["api", "agents", "v1" | _rest], path)
  end

  defp signed?(_conn), do: false

  defp read_signed(conn, opts) do
    opts = opts |> Keyword.put(:length, @limit) |> Keyword.put(:read_length, @limit + 1)

    case Plug.Conn.read_body(conn, opts) do
      {status, chunk, conn} when status in [:ok, :more] ->
        body = Map.get(conn.assigns, :raw_body, "") <> chunk
        if byte_size(body) > @limit, do: raise(Plug.Parsers.RequestTooLargeError)

        conn =
          conn
          |> Plug.Conn.assign(:raw_body, body)
          |> Plug.Conn.put_private(:signed_body_complete, status == :ok)

        {status, chunk, conn}

      other ->
        other
    end
  end
end

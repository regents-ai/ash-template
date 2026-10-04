defmodule AshTemplateWeb.SignedBodyReader do
  @moduledoc """
  Keeps the exact bytes of an agent's signed request body, so the sign-in
  service can check them against the request's signature
  (`AshTemplateWeb.Plugs.AgentWallet`). Every other body is read as before.
  """

  @limit 16_384

  def read_body(
        %{method: "POST", path_info: ["api", "v1", "rooms", _room, "messages"]} = conn,
        opts
      ) do
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

  def read_body(conn, opts), do: RegentIdentity.BodyReader.read_body(conn, opts)
end

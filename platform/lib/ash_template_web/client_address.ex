defmodule AshTemplateWeb.ClientAddress do
  @moduledoc """
  The key a request's address spends its post and search allowances under: the
  limiter key (`RegentHttp.ClientAddress.key/1`), keyed-hashed, so it can travel
  in a signed page token without naming the address. A page keeps the key of the
  request that rendered it.
  """

  @spec client_key(Plug.Conn.t()) :: String.t()
  def client_key(conn) do
    {address, _source} = RegentHttp.ClientAddress.key(conn)
    secret = AshTemplateWeb.Endpoint.config(:secret_key_base)

    :hmac
    |> :crypto.mac(:sha256, secret, :erlang.term_to_binary(address))
    |> binary_part(0, 16)
    |> Base.url_encode64(padding: false)
  end
end

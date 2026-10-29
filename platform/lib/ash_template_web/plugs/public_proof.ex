defmodule AshTemplateWeb.Plugs.PublicProof do
  @moduledoc """
  A public read needs no sign-in, so a request with no agent proof headers reads
  anonymously. A request that carries any of them is checked as every signed
  request is (`AshTemplateWeb.Plugs.AgentWallet`), and proof that fails is refused
  in the site's one shape, `{"error": {"code", "message", "hint"}}`, never read
  past. As there, the signature covers the method, path and body, so a signed read
  that sends a query string is refused (`unsupported_query`).
  """

  @behaviour Plug

  alias AshTemplateWeb.Plugs.AgentWallet

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    if Siwa.AgentAuthPlug.signed_request?(conn), do: AgentWallet.call(conn, opts), else: conn
  end
end

defmodule AshTemplateWeb.Plugs.PublicProof do
  @moduledoc """
  A public read needs no sign-in, so a request with no agent proof headers reads
  anonymously. A request that carries any of them has its proof checked by the
  sign-in service as every signed request's is, for the same wallet
  (`AshTemplateWeb.Plugs.AgentWallet.vouched/1`), and proof that fails is refused
  in the site's one shape, `{"error": {"code", "message", "hint"}}`, never read
  past. As there, the signature covers the method, path and body, so a signed read
  that sends a query string is refused (`unsupported_query`).

  Proof that holds signs nobody in: the read answers as it answers anyone, with no
  actor, nothing saved and no pairing check before it is sent.
  """

  @behaviour Plug
  @behaviour Siwa.AgentAuthPlug.Hooks

  alias AshTemplateWeb.Plugs.AgentWallet

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Siwa.AgentAuthPlug.signed_request?(conn),
      do: AgentWallet.check(conn, __MODULE__),
      else: conn
  end

  @impl Siwa.AgentAuthPlug.Hooks
  defdelegate before_verify(conn, headers), to: AgentWallet

  @impl Siwa.AgentAuthPlug.Hooks
  def accept(conn, data, _context) do
    with {:ok, _address, _book} <- AgentWallet.vouched(data), do: {:ok, conn}
  end

  @impl Siwa.AgentAuthPlug.Hooks
  defdelegate deny(conn, failure), to: AgentWallet
end

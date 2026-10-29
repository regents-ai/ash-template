defmodule AshTemplateWeb.ErrorsAdmin do
  @moduledoc """
  Keeps the saved errors at /admin/errors for Credits admins: a signed-in
  account the Credits `:admins` setting names (REGENT_CREDITS_ADMINS).
  `RegentPrivy.Owners` checks the request and the page with this module as the
  sign-in it reads: anyone else gets the site's ordinary not-found page, and a
  sign-in that ends or lapses cannot keep acting on the page, the way the
  product shell re-reads it (`AshTemplateWeb.Live.Session`).

  As a plug, after that check, it sends the page's own content security policy,
  with a nonce for the one style and one script element the error dashboard
  writes into its page.
  """

  @behaviour Plug
  @behaviour RegentPrivy.Owners

  import Plug.Conn

  alias AshTemplate.Accounts.SessionAuthority
  alias AshTemplateWeb.ContentSecurityPolicy

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", ContentSecurityPolicy.errors(nonce))
  end

  @impl RegentPrivy.Owners
  def owners, do: Application.fetch_env!(:regent_credits, :admins)

  @impl RegentPrivy.Owners
  def signed_in(session) do
    case session |> SessionAuthority.claim() |> SessionAuthority.resolve() do
      {lineage, %{privy_user_id: id} = account, _lapses_at} when is_binary(lineage) ->
        {:ok, id, {lineage, account.id}}

      _signed_out ->
        :signed_out
    end
  end

  @impl RegentPrivy.Owners
  def still_signed_in({lineage, account_id}) do
    case SessionAuthority.leased_account(lineage, account_id) do
      %{privy_user_id: id} -> {:ok, id}
      nil -> :signed_out
    end
  end
end

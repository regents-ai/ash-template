defmodule AshTemplateWeb.ErrorsAdmin do
  @moduledoc """
  The site's admins, for the saved errors at /admin/errors and the messages left
  for the team at /admin/messages: a signed-in account the site's `:admins` setting
  names (config/config.exs). `RegentPrivy.Owners` keeps both pages with this module
  as the sign-in it reads, through the session rows (`SessionAuthority`): anyone
  else gets the site's ordinary not-found page, and an open page checks the sign-in
  again on every navigation, press, message and background result, so a sign-in
  that ends or lapses cannot keep acting on the page.

  As a plug, after that check, it sends the page's own content security policy,
  with a nonce for the one style and one script element the error dashboard writes
  into its page. As the `:admin` hook it gives the team page its actor, `:admin`,
  from the Privy id the check put on the page; `RegentAgents.Checks.Admin` checks
  that actor again in each policy.
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

  def on_mount(:admin, _params, _session, socket) do
    {:cont,
     Phoenix.Component.assign(socket, :admin, %RegentAgents.Person{
       privy_user_id: socket.assigns.owner_privy_user_id,
       role: :admin
     })}
  end

  @impl RegentPrivy.Owners
  def owners, do: Application.fetch_env!(:ash_template, :admins)

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

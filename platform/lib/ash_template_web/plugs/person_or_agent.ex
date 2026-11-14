defmodule AshTemplateWeb.Plugs.PersonOrAgent do
  @moduledoc """
  Who calls an API that a person uses with their own sign-in on this site, and an
  agent they paired uses for them. An agent's signed request
  (`AshTemplateWeb.Plugs.AgentWallet`) acts as its person while its person's
  latest sign-in here names a wallet, and is refused otherwise. Any other request
  is the person's session cookie, whose request that changes something carries
  the session's forms token in x-csrf-token, as the site's pages send it; one
  without it counts as signed out, so another site's page can never act with the
  person's cookie.

  Assigns `:actor`: the signed-in `AshTemplate.Actors.Human`, the paired
  `AshTemplate.Actors.Agent`, or nil for a signed-out request, which the API
  behind it refuses in its own words.
  """

  @behaviour Plug

  import Plug.Conn

  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias AshTemplateWeb.PrivySessionController

  @forms_token Plug.CSRFProtection.init(with: :clear_session)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if Siwa.AgentAuthPlug.signed_request?(conn),
      do: agent(conn),
      else: person(conn)
  end

  # An agent's signed request acts as the person it is paired with, or not at all.
  defp agent(conn) do
    case AgentWallet.call(conn, []) do
      %{halted: true} = conn -> conn
      %{assigns: %{actor: %Agent{pairing: :active}}} = conn -> conn
      conn -> refuse(conn, AgentWallet.not_person_code(conn.assigns.actor))
    end
  end

  # The person's own sign-in on this site: the session cookie its pages hold.
  defp person(conn) do
    conn =
      conn
      |> fetch_session()
      |> Plug.CSRFProtection.call(@forms_token)
      |> PrivySessionController.enforce_authority()

    case conn.assigns.current_human_account do
      %{} = account -> assign(conn, :actor, Human.for_account(account))
      nil -> assign(conn, :actor, nil)
    end
  end

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(AgentWallet.not_person_refusals(), code)

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: %{code: code, message: message, hint: hint}})
    |> halt()
  end
end

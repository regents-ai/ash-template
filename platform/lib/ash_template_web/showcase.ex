defmodule AshTemplateWeb.Showcase do
  @moduledoc """
  The showcase setting and the gate on every route it covers.

  The setting (`:showcase`, from `ASH_TEMPLATE_SHOWCASE` in `config/runtime.exs`)
  is one of:

    * `:local` — development: the showcase pages and the build skills answer only
      a loopback visitor on a loopback address, marked `noindex` and `no-store`;
      the motion lab is open.
    * `:public` — the hosted demo: they are public pages, listed in the sitemap
      and `/llms.txt`.
    * `:off` — a new site's production: none of them exist.

  The gate takes the part of the site it guards:

    * `:pages` — the showcase pages, the wallet page and the build skills.
    * `:lab` — the wallet lab at `/showcase/onchain` and the Credits lab at
      `/showcase/credits`, which send to chains on this machine, so they exist
      only in `:local`.
    * `:motion_lab` — `/animations`, which exists unless the setting is `:off`.

  A request the gate refuses answers the site's own 404. A connected mount it
  refuses goes to the home page.
  """
  @behaviour Plug
  import Plug.Conn

  @loopback_hosts ~w(localhost 127.0.0.1 ::1 [::1])

  @doc "The showcase setting."
  def mode, do: Application.fetch_env!(:ash_template, :showcase)

  @doc "True when the showcase pages are public and listed."
  def public?, do: mode() == :public

  @doc "True when the home page links to the showcase, the motion lab and the skills."
  def linked?, do: mode() != :off

  @impl Plug
  def init(part), do: part

  @impl Plug
  def call(conn, part) do
    admits?(part, mode(), conn.remote_ip, conn.host) or raise AshTemplateWeb.NotFoundError

    if mode() == :local and part != :motion_lab,
      do: register_before_send(conn, &unlisted/1),
      else: conn
  end

  @doc "Whether Privy sign-in is configured here; never returns configuration values."
  def privy_mode do
    config = Application.get_env(:ash_template, :privy, [])

    if Enum.all?([:app_id, :verification_key], &present?(config[&1])),
      do: :configured,
      else: :unconfigured
  end

  def on_mount(part, _params, _session, socket) do
    if admits_mount?(part, socket),
      do: {:cont, Phoenix.Component.assign(socket, :local?, mode() == :local)},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
  end

  # A disconnected render passed the plug; a connected mount is checked again.
  defp admits_mount?(part, socket) do
    if Phoenix.LiveView.connected?(socket) do
      %{address: address} = Phoenix.LiveView.get_connect_info(socket, :peer_data)
      %{host: host} = Phoenix.LiveView.get_connect_info(socket, :uri)
      admits?(part, mode(), address, host)
    else
      true
    end
  end

  defp admits?(:motion_lab, mode, _address, _host), do: mode != :off
  defp admits?(:pages, :public, _address, _host), do: true
  defp admits?(_part, :local, address, host), do: loopback?(address, host)
  defp admits?(_part, _mode, _address, _host), do: false

  # Local showcase answers are never kept or indexed, whatever the page set.
  defp unlisted(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp loopback?({127, _, _, _}, host) when host in @loopback_hosts, do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}, host) when host in @loopback_hosts, do: true
  defp loopback?(_address, _host), do: false
end

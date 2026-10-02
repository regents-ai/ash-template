defmodule AshTemplateWeb.Live.LaunchGateHook do
  @moduledoc """
  Keeps product LiveViews closed while the launch gate is closed: on mounts that
  reach the socket without a fresh request (reconnects, live navigation from a
  page loaded before the gate closed) and on every navigation after, since a
  patch between the routes it covers never asks for a new page.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias AshTemplateWeb.Plugs.LaunchGate

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- gate(socket) do
      navigation = fn _params, _uri, socket -> gate(socket) end
      {:cont, attach_hook(socket, :launch_gate, :handle_params, navigation)}
    end
  end

  defp gate(socket) do
    if LaunchGate.app_surfaces_enabled?(),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/")}
  end
end

defmodule AshTemplateWeb.Live.LaunchGateHook do
  @moduledoc """
  Keeps product LiveViews closed while the launch gate is closed: on mounts that
  reach the socket without a fresh request (reconnects, live navigation from a
  page loaded before the gate closed), on every navigation after, since a patch
  between the routes it covers never asks for a new page, and on every event the
  LiveView itself handles. A LiveComponent's events reach the component without
  passing here; the gate is read from the release's settings, so closing it
  restarts the site and no product page, nor any component in one, mounts again.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias AshTemplateWeb.Plugs.LaunchGate

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- gate(socket) do
      {:cont,
       socket
       |> attach_hook(:launch_gate, :handle_params, fn _params, _uri, socket -> gate(socket) end)
       |> attach_hook(:launch_gate_events, :handle_event, &gate_event/3)}
    end
  end

  defp gate_event(_event, _params, socket) do
    if LaunchGate.app_surfaces_enabled?(), do: {:cont, socket}, else: {:halt, %{}, socket}
  end

  defp gate(socket) do
    if LaunchGate.app_surfaces_enabled?(),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/")}
  end
end

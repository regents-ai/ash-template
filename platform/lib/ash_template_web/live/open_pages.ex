defmodule AshTemplateWeb.Live.OpenPages do
  @moduledoc """
  Bounds how many live pages one internet address holds open on this machine.

  Each open page is two processes that keep their memory for as long as the
  browser tab stays connected, so one address opening thousands could take the
  machine's memory from everyone else. Every connected page registers under the
  address key of the request that rendered it (`AshTemplateWeb.ClientAddress`),
  and the registry forgets a page the moment its process ends, so there is
  nothing to count down or sweep. A page past the limit is sent to a plain page
  that says so.

  Every LiveView runs this (`AshTemplateWeb.live_view/0`), so every
  `live_session` passes `session: {AshTemplateWeb.Live.Session, :render_context, []}`:
  a connected socket cannot see the address header the rendering request carried.
  The error dashboard's pages are the library's own and admin-only, and are not
  counted.

  The count is this machine's: an address spread over several machines holds up
  to the limit on each. A page that moves to another page leaves and joins in
  quick succession, so an address holding exactly the limit can be refused a
  move while the page it left is still being forgotten.
  """

  import Phoenix.LiveView, only: [connected?: 1, redirect: 2]

  @limit 40

  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: __MODULE__)

  def on_mount(:default, _params, session, socket) do
    if connected?(socket),
      do: admit(socket, Map.fetch!(session, "client_key")),
      else: {:cont, socket}
  end

  # Registered first and counted after, so pages arriving together cannot all
  # read a count below the limit and pass.
  defp admit(socket, key) do
    {:ok, _owner} = Registry.register(__MODULE__, key, nil)

    if Registry.count_match(__MODULE__, key, :_) > @limit do
      Registry.unregister(__MODULE__, key)
      :telemetry.execute([:ash_template, :open_pages, :refused], %{count: 1}, %{})
      {:halt, redirect(socket, to: "/too-many-pages")}
    else
      {:cont, socket}
    end
  end
end

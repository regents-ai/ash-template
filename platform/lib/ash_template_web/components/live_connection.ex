defmodule AshTemplateWeb.LiveConnection do
  @moduledoc """
  The note a live form shows while its page has no live connection: when the page
  could not connect, and from half a second after a connection drops until it is
  back. Meanwhile the form's buttons are disabled, so a press is visibly
  unavailable rather than doing nothing. LiveView runs `phx-disconnected` and
  `phx-connected`; the server never renders `disabled` on what `controls` names,
  so its patches never undo either.
  """
  use AshTemplateWeb, :html

  attr :id, :string, required: true
  attr :controls, :string, required: true, doc: "a selector for the buttons to disable"

  def offline(assigns) do
    ~H"""
    <Regent.Primitives.notice
      id={@id}
      tone="warning"
      hidden
      phx-disconnected={JS.show() |> JS.set_attribute({"disabled", ""}, to: @controls)}
      phx-connected={JS.hide() |> JS.remove_attribute("disabled", to: @controls)}
    >
      Not connected. Trying again…
    </Regent.Primitives.notice>
    """
  end
end

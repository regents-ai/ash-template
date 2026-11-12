defmodule AshTemplateWeb.AgentMessageLive do
  @moduledoc """
  The Agent Message form's own live view on a plain page: the dialog
  (`AshTemplateWeb.Components.AgentMessage.dialog/1` with `conn`) draws it with
  `live_render(@conn, …)`, so it is an open page of its own
  (`AshTemplateWeb.Live.OpenPages`) and reads the sign-in itself
  (`AshTemplateWeb.Live.Session`). It holds only the form
  (`AshTemplateWeb.Components.AgentMessage.Form`), which a live page places
  directly.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplate.AccessContext
  alias AshTemplateWeb.Components.AgentMessage.Form

  on_mount {AshTemplateWeb.Live.Session, :load_human}

  @impl true
  def mount(_params, %{"id" => id, "topic" => topic}, socket),
    do: {:ok, assign(socket, id: id, topic: topic), layout: false}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id={@id}
      topic={@topic}
      account={account(@access_context)}
      lease={@session_lease}
      client_key={@client_key}
    />
    """
  end

  defp account(%AccessContext{principal: {:human, account}}), do: account
  defp account(_signed_out), do: nil
end

defmodule AshTemplateWeb.AgentMessageLive do
  @moduledoc """
  The form inside the Agent Message dialog (`AshTemplateWeb.Components.AgentMessage`):
  a signed-in person leaves a private message for the site's team under the
  dialog's topic, through the same `leave` action an agent's message takes, and
  sees its receipt. A signed-out visitor sees nothing here. Each field is
  checked when the person leaves it, never while they type. The page draws it
  with `live_render(@conn, …)`, so it is an open page of its own
  (`AshTemplateWeb.Live.OpenPages`) and reads the sign-in itself
  (`AshTemplateWeb.Live.Session`); every press re-reads it, and the message is
  left as the account that sign-in names at that moment.
  """

  use AshTemplateWeb, :live_view

  alias AshTemplate.AccessContext
  alias AshTemplate.Actors.Human
  alias AshTemplate.Messages
  alias AshTemplateWeb.FormErrors
  alias Regent.Primitives

  on_mount {AshTemplateWeb.Live.Session, :load_human}

  @impl true
  def mount(_params, %{"topic" => topic}, socket) do
    socket = assign(socket, topic: topic, receipt: nil)
    {:ok, assign(socket, :form, new_form(socket)), layout: false}
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  # Left as the account the sign-in names now, which the press has just re-read.
  def handle_event("leave", %{"message" => params}, socket) do
    case socket |> new_form() |> submit(params) do
      {:ok, message} ->
        {:noreply,
         assign(socket, receipt: Messages.Message.receipt(message), form: new_form(socket))}

      {:error, form} ->
        {:noreply, assign(socket, receipt: nil, form: form)}
    end
  end

  defp submit(nil, _params), do: {:error, nil}
  defp submit(form, params), do: AshPhoenix.Form.submit(form, params: params)

  defp new_form(socket) do
    case socket.assigns.access_context do
      %AccessContext{principal: {:human, account}} ->
        Messages.form_to_leave_message(
          actor: Human.for_account(account),
          as: "message",
          context: %{client_key: socket.assigns.client_key},
          prepare_params: fn params, _phase -> Map.put(params, "topic", socket.assigns.topic) end
        )
        |> to_form()

      _signed_out ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section :if={@form} class="agent-message__form" aria-labelledby="agent-message-form-title">
      <h3 id="agent-message-form-title">Your message</h3>
      <p class="code-card__note">Or leave one yourself. Only this site's team reads it.</p>
      <Primitives.notice :if={@receipt} tone="success" id="agent-message-receipt">
        Sent {time(@receipt.inserted_at)}. Receipt <code>{@receipt.id}</code>
      </Primitives.notice>
      <.form
        for={@form}
        id="agent-message-form"
        class="agent-message__fields"
        phx-change="validate"
        phx-submit="leave"
      >
        <Primitives.field
          :let={field}
          id="agent-message-body"
          label="Message"
          errors={FormErrors.messages(@form[:body])}
        >
          <textarea
            id={field.id}
            name={@form[:body].name}
            rows="4"
            maxlength="2000"
            phx-debounce="blur"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          >{@form[:body].value}</textarea>
        </Primitives.field>
        <Primitives.field
          :let={field}
          id="agent-message-reply-to"
          label="Reply to"
          errors={FormErrors.messages(@form[:reply_to])}
        >
          <input
            id={field.id}
            name={@form[:reply_to].name}
            value={@form[:reply_to].value}
            maxlength="200"
            autocomplete="email"
            phx-debounce="blur"
            aria-invalid={field.aria_invalid}
            aria-describedby={field.described_by}
          />
          <:hint>Optional. An email, a room or a profile where the team can answer you.</:hint>
        </Primitives.field>
        <Primitives.button type="submit" phx-disable-with="Sending…">Send</Primitives.button>
      </.form>
    </section>
    """
  end

  defp time(at), do: Calendar.strftime(at, "%-d %b %Y, %H:%M UTC")
end

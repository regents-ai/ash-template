defmodule AshTemplateWeb.NotesLive do
  @moduledoc """
  The signed-in person's notes: a form bound to the note's own Ash actions and a
  list every open page of theirs keeps current, each note with the label Jev
  chose for it. Their titles also fill the shell's sidebar, where choosing one
  opens it in the form.

  Saving never touches the list directly. Each change reaches the list the same
  way, whether it came from this page, another tab or the API: the note's and
  its label decision's PubSub notifiers publish it after the transaction
  commits, the shell holds the subscription, and hands it on here as
  `send_update(NotesLive, id: "notes", change: {event, note_or_decision})`.
  Any change but a delete reads the note again with its latest label.
  """

  use AshTemplateWeb, :live_component

  alias AshTemplate.Actors.Human
  alias AshTemplate.Notes
  alias AshTemplate.Notes.{Decision, Note}
  alias AshTemplateWeb.FormErrors
  alias AshTemplateWeb.Live.Session
  alias AshTemplateWeb.Read
  alias Regent.Primitives

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_events(&take_account/2)
     |> assign(actor: nil, notes: %Read{}, form: nil, editing: nil, notice: nil)
     |> stream(:notes, [])
     |> stream(:note_links, [], dom_id: &"note-link-#{&1.id}")}
  end

  @impl true
  def update(%{change: {event, note}}, socket), do: {:ok, apply_change(socket, event, note)}

  # The shell renders this with every update of its own, so the notes are read
  # again only when the person behind them changes.
  def update(%{id: id, lease: lease, account: account}, socket) do
    actor = account && Human.for_account(account)
    socket = assign(socket, id: id, lease: lease)

    if actor == socket.assigns.actor,
      do: {:ok, socket},
      else: {:ok, socket |> assign(:actor, actor) |> load()}
  end

  @impl true
  def handle_async(
        {Read, :notes, generation} = name,
        result,
        %{assigns: %{notes: %Read{generation: generation}}} = socket
      ) do
    {:noreply, socket |> Read.settle(name, result) |> show_notes()}
  end

  def handle_async({Read, :notes, _superseded}, _result, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate", %{"note" => params}, socket),
    do: {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}

  def handle_event("save", %{"note" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _note} -> {:noreply, new_form(socket)}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Notes.get_my_note(id, actor: socket.assigns.actor) do
      {:ok, %Note{} = note} -> {:noreply, edit_form(socket, note)}
      failure -> {:noreply, assign(socket, :notice, notice(failure, "loaded"))}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, new_form(socket)}

  def handle_event("rate", %{"id" => id, "report" => report}, socket) do
    actor = socket.assigns.actor

    with {:ok, %Decision{} = decision} <- Notes.get_label_decision(id, actor: actor),
         {:ok, _decision} <- Notes.rate_label(decision, report, actor: actor) do
      {:noreply, assign(socket, :notice, nil)}
    else
      {:error, %Ash.Error.Invalid{}} ->
        {:noreply, assign(socket, :notice, "That label has already been rated.")}

      failure ->
        {:noreply, assign(socket, :notice, notice(failure, "rated"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    actor = socket.assigns.actor

    with {:ok, %Note{} = note} <- Notes.get_my_note(id, actor: actor),
         :ok <- Notes.destroy_note(note, actor: actor) do
      {:noreply, assign(socket, :notice, nil)}
    else
      failure -> {:noreply, assign(socket, :notice, notice(failure, "deleted"))}
    end
  end

  # The account as it reads now, before each event
  # (`Session.check_component_events/2`).
  defp take_account(socket, account), do: assign(socket, :actor, Human.for_account(account))

  @impl true
  def render(assigns) do
    ~H"""
    <article id="notes-page" class="account-page">
      <.portal id="notes-sidebar" target="#shell-sidebar-page">
        <div class="shell-sidebar__page">
          <ul :if={@actor} id="notes-sidebar-list" class="shell-sidebar__list" phx-update="stream">
            <li id="notes-sidebar-empty" class="shell-sidebar__empty">No notes yet.</li>
            <li :for={{dom_id, note} <- @streams.note_links} id={dom_id}>
              <button type="button" phx-click="edit" phx-value-id={note.id} phx-target={@myself}>
                {note.title}
              </button>
            </li>
          </ul>
          <p :if={!@actor} class="shell-sidebar__empty">Sign in to see your notes here.</p>
        </div>
      </.portal>
      <header class="account-heading">
        <p class="account-kicker">Ash Template</p>
        <h1 tabindex="-1">Notes</h1>
        <p class="account-lede">
          Notes only you can read. Every page you have open shows each change straight away.
          Each note you save is given a label, chosen automatically.
        </p>
      </header>

      <section :if={is_nil(@actor)} class="account-panel account-signed-out">
        <h2>Sign in to keep notes</h2>
        <p>Your notes appear here once you are signed in.</p>
        <Primitives.button type="button" data-account-target="sign-in">Sign in</Primitives.button>
      </section>

      <div :if={@actor} class="account-grid">
        <section class="account-panel" aria-labelledby="note-form-title">
          <h2 id="note-form-title">{if @editing, do: "Edit note", else: "New note"}</h2>
          <.form
            for={@form}
            id="note-form"
            class="notes-form"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
          >
            <Primitives.field
              :let={field}
              id="note-title"
              label="Title"
              errors={FormErrors.messages(@form[:title])}
            >
              <input
                id={field.id}
                name={@form[:title].name}
                value={@form[:title].value}
                maxlength="120"
                autocomplete="off"
                phx-debounce="300"
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
              />
            </Primitives.field>
            <Primitives.field
              :let={field}
              id="note-body"
              label="Note"
              errors={FormErrors.messages(@form[:body])}
            >
              <textarea
                id={field.id}
                name={@form[:body].name}
                rows="6"
                maxlength="10000"
                phx-debounce="300"
                aria-invalid={field.aria_invalid}
                aria-describedby={field.described_by}
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:body].value)}</textarea>
            </Primitives.field>
            <div class="notes-form__actions">
              <Primitives.button type="submit" phx-disable-with="Saving…">
                {if @editing, do: "Save changes", else: "Add note"}
              </Primitives.button>
              <Primitives.button
                :if={@editing}
                type="button"
                variant="secondary"
                phx-click="cancel"
                phx-target={@myself}
              >
                Cancel
              </Primitives.button>
            </div>
          </.form>
        </section>

        <section class="account-panel" aria-labelledby="notes-list-title">
          <h2 id="notes-list-title">Your notes</h2>
          <Primitives.notice :if={@notice} tone="warning">{@notice}</Primitives.notice>
          <Primitives.notice :if={@notes.state in [:error, :stale]} tone="error">
            Your notes couldn’t be loaded. Refresh the page to try again.
          </Primitives.notice>
          <p :if={@notes.state == :loading} class="rg-muted">Loading your notes…</p>
          <ul id="notes-list" class="notes-list" data-state={@notes.state} phx-update="stream">
            <li id="notes-empty" class="notes-empty rg-muted">
              No notes yet. Write your first one with the form.
            </li>
            <li :for={{dom_id, note} <- @streams.notes} id={dom_id} class="notes-item">
              <h3>{note.title}</h3>
              <p :if={note.body}>{note.body}</p>
              <p :if={note.changed_by_agent} class="rg-muted">
                Saved by your agent {RegentFormat.short_address(note.changed_by_agent.wallet_address)}
              </p>
              <.label decision={note.label_decision} target={@myself} />
              <div class="notes-item__actions">
                <Primitives.button
                  type="button"
                  variant="quiet"
                  phx-click="edit"
                  phx-value-id={note.id}
                  phx-target={@myself}
                >
                  Edit
                </Primitives.button>
                <Primitives.button
                  type="button"
                  variant="quiet"
                  phx-click="delete"
                  phx-value-id={note.id}
                  phx-target={@myself}
                  data-confirm="Delete this note?"
                >
                  Delete
                </Primitives.button>
              </div>
            </li>
          </ul>
        </section>
      </div>
    </article>
    """
  end

  attr :decision, Decision, default: nil
  attr :target, :any, required: true

  defp label(%{decision: nil} = assigns), do: ~H""

  defp label(%{decision: %Decision{state: :pending}} = assigns) do
    ~H"""
    <p class="notes-label rg-muted" data-label-state="pending">Choosing a label…</p>
    """
  end

  defp label(%{decision: %Decision{state: :failed}} = assigns) do
    ~H"""
    <p class="notes-label rg-muted" data-label-state="failed">No label this time.</p>
    """
  end

  defp label(%{decision: %Decision{state: :answered}} = assigns) do
    ~H"""
    <div class="notes-label" data-label-state="answered">
      <Primitives.status tone="info">{String.capitalize(@decision.choice)}</Primitives.status>
      <span :if={@decision.report == :fits} class="rg-muted">You said this label fits.</span>
      <span :if={@decision.report == :does_not_fit} class="rg-muted">
        You said this label doesn’t fit.
      </span>
      <span :if={is_nil(@decision.report)} class="notes-label__rate">
        <span class="rg-muted">Does it fit?</span>
        <Primitives.button
          :for={{report, text} <- [fits: "Fits", does_not_fit: "Doesn’t fit"]}
          type="button"
          variant="quiet"
          phx-click="rate"
          phx-value-id={@decision.id}
          phx-value-report={report}
          phx-target={@target}
        >
          {text}
        </Primitives.button>
      </span>
    </div>
    """
  end

  defp load(%{assigns: %{actor: nil}} = socket) do
    socket
    |> Read.clear(:notes)
    |> stream(:notes, [], reset: true)
    |> stream(:note_links, [], reset: true)
    |> assign(form: nil, editing: nil, notice: nil)
  end

  defp load(%{assigns: %{actor: actor}} = socket) do
    socket
    |> Read.start(:notes, actor.human_account_id, fn -> Notes.list_my_notes(actor: actor) end)
    |> new_form()
  end

  # A failed read keeps the notes already on the page, so only a read that
  # landed replaces them.
  defp show_notes(%{assigns: %{notes: %Read{state: state, value: notes}}} = socket)
       when state in [:ready, :empty] do
    socket
    |> stream(:notes, notes, reset: true)
    |> stream(:note_links, notes, reset: true)
  end

  defp show_notes(socket), do: socket

  defp apply_change(socket, "destroy", %Note{} = note) do
    socket = socket |> stream_delete(:notes, note) |> stream_delete(:note_links, note)
    if socket.assigns.editing == note.id, do: new_form(socket), else: socket
  end

  defp apply_change(socket, _event, %Note{id: id}), do: refresh(socket, id)
  defp apply_change(socket, _event, %Decision{note_id: id}), do: refresh(socket, id)

  # A note already on the page is updated where it stands; a new one goes on
  # top. One deleted since the change leaves the page as it is.
  defp refresh(socket, id) do
    case Notes.get_my_note(id, actor: socket.assigns.actor) do
      {:ok, %Note{} = note} ->
        socket
        |> stream_insert(:notes, note, at: 0)
        |> stream_insert(:note_links, note, at: 0)

      {:ok, nil} ->
        socket

      {:error, _failure} ->
        assign(socket, :notice, "A change couldn’t be shown. Refresh the page to see it.")
    end
  end

  # A note that is gone (deleted elsewhere, or never this person's) says so; a
  # database that could not answer says to try again.
  defp notice({:ok, nil}, _verb), do: "That note is no longer here."
  defp notice({:error, %Ash.Error.Invalid{}}, _verb), do: "That note is no longer here."
  defp notice({:error, _failure}, verb), do: "That note couldn’t be #{verb}. Try again."

  defp new_form(socket) do
    form = Notes.form_to_create_note(actor: socket.assigns.actor, as: "note")
    assign(socket, form: to_form(form), editing: nil, notice: nil)
  end

  defp edit_form(socket, note) do
    form = Notes.form_to_update_note(note, actor: socket.assigns.actor, as: "note")
    assign(socket, form: to_form(form), editing: note.id, notice: nil)
  end
end

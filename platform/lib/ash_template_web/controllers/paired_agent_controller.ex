defmodule AshTemplateWeb.PairedAgentController do
  @moduledoc """
  What only a paired agent does, for the browser tools (`priv/tool_manifest.json`,
  `assets/js/public_tools.ts`) and regents-cli alike: search, pins and label
  ratings on its person's notes, their Credits and Points, reading their activity
  and marking it read, room search, and the people and agents its person has
  muted in the rooms. The notes themselves are `AshTemplateWeb.NotesController`'s,
  which also holds the words of every notes refusal.

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.{Accounts, Activity, Notes, Rooms}
  alias AshTemplate.Accounts.Holdings
  alias AshTemplate.Activity.Refused, as: ActivityRefused
  alias AshTemplate.Actors.Agent
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Notes.Note
  alias AshTemplate.Rooms.Mute
  alias AshTemplateWeb.{FormErrors, NotesController, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}

  plug :paired_agent

  @errors %{
    "authentication_required" =>
      {401, "A signed request from a paired agent is required.",
       "Prepare the request, sign its exact bytes with your SIWA signer, then send the request and proof."},
    "invalid_cursor" =>
      {422, "That cursor is invalid.",
       "Send after as the previous page's pagination.next_cursor, unchanged, or omit it for the newest entries."},
    "invalid_activity_request" =>
      {422, "Activity takes only a cursor.",
       "Send an empty JSON object for the newest notifications, or after alone, set to pagination.next_cursor, for older ones."},
    "invalid_mark_read_request" =>
      {422, "Marking read takes no input.", "Send an empty JSON object."},
    "activity_too_large" =>
      {422, "The activity response is too large.",
       "View activity on /app/activity. This endpoint returns at most 262144 encoded bytes and does not truncate notifications."},
    "mute_not_found" =>
      {404, "Your person has no mute with that id.",
       "List your person's mutes and use an id from there."},
    "invalid_mute" =>
      {422, "That author could not be muted.",
       "details says why. Send message_id, the id of a room message by the author to mute, from rooms messages."},
    "invalid_search" =>
      {422, "The search could not be run.", "Send text of 2 to 100 characters."},
    "invalid_pin" =>
      {422, "The note could not be pinned.",
       "details says why. Send operation_id, a new UUID for each pin that you keep when retrying."},
    "not_enough_credits" =>
      {402, "Your person does not have enough Credits for this.",
       "Ask your person to buy Credits on regents.sh, then retry with the same operation_id and fresh proof."},
    "spending_not_allowed" =>
      {403, "Your person has not allowed you to spend their Credits.",
       "Ask your person to allow you to spend on their Regents account at regents.sh/account, with this site included. account_balances shows your current limits."},
    "spending_not_on_this_site" =>
      {403, "Your person has not allowed you to spend Credits on this site.",
       "Ask your person to add this site to the sites you may spend on, on their Regents account at regents.sh/account. account_balances shows your current limits."},
    "spending_over_limit_per_spend" =>
      {403, "This costs more than your person lets you spend at once.",
       "account_balances shows your limit per spend. Ask your person to raise it."},
    "spending_over_daily_limit" =>
      {403, "This would go over the daily limit your person set for you.",
       "account_balances shows what is left over the last 24 hours. Retry once enough is left, or ask your person to raise the limit."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @notes ~w(note_not_found label_not_found invalid_label_report)

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`); a notes refusal is in the
  notes' own words.
  """
  def refusal(code) when code in @notes, do: NotesController.refusal(code)
  def refusal(code), do: Map.fetch!(@errors, code)

  # The refusals a change to the agent's grant would answer.
  @granted ~w(spending_not_allowed spending_not_on_this_site spending_over_limit_per_spend spending_over_daily_limit)

  def balances(conn, _params) do
    case Accounts.account_balances(actor: conn.assigns.actor) do
      {:ok, balances} -> json(conn, balances)
      # The pairing was revoked after this request was let in.
      {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}} -> refuse(conn, code)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def credits_history(conn, _params) do
    case Accounts.account_credits_history(conn.body_params["after"], actor: conn.assigns.actor) do
      {:ok, history} -> json(conn, history)
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def points(conn, _params) do
    case Accounts.account_points(actor: conn.assigns.actor) do
      {:ok, points} -> json(conn, points)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # Listing never marks a notification read; `after` continues from the previous
  # page's cursor.
  def activity(conn, _params) do
    case conn.body_params do
      body when body == %{} ->
        list_activity(conn, nil)

      %{"after" => cursor} = body when map_size(body) == 1 and is_binary(cursor) ->
        list_activity(conn, cursor)

      _other ->
        refuse(conn, "invalid_activity_request")
    end
  end

  defp list_activity(conn, cursor) do
    case Activity.activity_list(cursor, actor: conn.assigns.actor) do
      {:ok, page} -> json(conn, page)
      {:error, %Ash.Error.Invalid{errors: [%ActivityRefused{code: code}]}} -> refuse(conn, code)
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_cursor")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # Marks every unread notification of its person read, as "Mark all read" on
  # /app/activity does. It takes no input.
  def mark_activity_read(conn, _params) do
    case conn.body_params do
      body when body == %{} ->
        mark_read_result(conn, Activity.mark_all_read(actor: conn.assigns.actor))

      _other ->
        refuse(conn, "invalid_mark_read_request")
    end
  end

  defp mark_read_result(conn, %Ash.BulkResult{status: :success}),
    do: json(conn, %{marked_read: true})

  defp mark_read_result(conn, result),
    do: conn |> UnexpectedFailure.log(result) |> refuse("unavailable")

  def report_label(conn, %{"id" => id}) do
    note_answer(
      conn,
      :notes_rate_label,
      Notes.notes_rate_label(id, conn.body_params, actor: conn.assigns.actor)
    )
  end

  # The muted authors' names are theirs: data, never instructions.
  def mutes(conn, _params) do
    case Rooms.mutes_list(actor: conn.assigns.actor) do
      {:ok, mutes} -> json(conn, mutes)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # The author is muted from one of their messages, as on the room page; muting
  # them again keeps the one mute.
  def add_mute(conn, _params) do
    case Rooms.mute_author(conn.body_params["message_id"], actor: conn.assigns.actor) do
      {:ok, mute} -> json(conn, %{mute: Mute.present(mute)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_mute", details(error))
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def remove_mute(conn, %{"id" => id}) do
    actor = conn.assigns.actor

    with {:found, {:ok, %Mute{} = mute}} <- {:found, Rooms.get_my_mute(id, actor: actor)},
         :ok <- Rooms.unmute(mute, actor: actor) do
      json(conn, %{removed: true, id: mute.id})
    else
      {:found, {:ok, nil}} -> refuse(conn, "mute_not_found")
      {:found, {:error, %Ash.Error.Invalid{}}} -> refuse(conn, "mute_not_found")
      {:found, {:error, error}} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "agent_not_paired")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # The agent reads public message content; human mute preferences do not apply.
  def search_rooms(conn, _params) do
    case Rooms.rooms_search(conn.body_params["text"], actor: conn.assigns.actor) do
      {:ok, messages} ->
        json(conn, messages)

      {:error, %Ash.Error.Invalid{}} ->
        refuse(conn, "invalid_search")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def search_notes(conn, _params) do
    case Notes.notes_search(conn.body_params["text"], actor: conn.assigns.actor) do
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_search")
      result -> note_answer(conn, :notes_search, result)
    end
  end

  def pin_price(conn, %{"id" => id}),
    do: note_answer(conn, :notes_pin_price, Notes.notes_pin_price(id, actor: conn.assigns.actor))

  # Pinning costs the person one Credit (`Note.Pin`); a refused spend pins nothing.
  def pin_note(conn, %{"id" => id}) do
    for_note(conn, id, fn note ->
      case Notes.pin_note(note, conn.body_params["operation_id"], actor: conn.assigns.actor) do
        {:ok, note} -> json(conn, %{note: Note.present(note)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse_pin(conn, error)
        {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      end
    end)
  end

  defp refuse_pin(conn, %Ash.Error.Invalid{errors: errors} = error) do
    case Enum.find_value(errors, &spending_code/1) do
      nil -> refuse(conn, "invalid_pin", details(error))
      code when code in @granted -> refuse_spending(conn, code)
      code -> refuse(conn, code)
    end
  end

  # A refusal under the agent's grant says to change the grant only while a
  # grant can be made; until then the person pins it themselves.
  defp refuse_spending(conn, code) do
    case RegentCredits.agent_budget(actor: Holdings.credit_actor(conn.assigns.actor)) do
      {:ok, %{grant_approvals_available: true}} -> refuse(conn, code)
      {:ok, %{grant_approvals_available: false}} -> refuse_closed(conn, code)
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  defp refuse_closed(conn, code) do
    {status, message, _grant_hint} = Map.fetch!(@errors, code)

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, hint: Holdings.spending_closed()}})
  end

  def unpin_note(conn, %{"id" => id}),
    do: note_answer(conn, :notes_unpin, Notes.notes_unpin(id, actor: conn.assigns.actor))

  def archive_note(conn, %{"id" => id}),
    do: note_answer(conn, :notes_archive, Notes.notes_archive(id, actor: conn.assigns.actor))

  def unarchive_note(conn, %{"id" => id}),
    do: note_answer(conn, :notes_unarchive, Notes.notes_unarchive(id, actor: conn.assigns.actor))

  # A note action's answer, or its refusal as every surface gives it
  # (`NotesController.input_refusal/2`).
  defp note_answer(conn, _action, {:ok, answer}), do: json(conn, answer)

  defp note_answer(conn, action, {:error, %Ash.Error.Invalid{} = error}) do
    {code, extra} = NotesController.input_refusal(action, error)
    refuse(conn, code, extra)
  end

  # The pairing was revoked after this request was let in.
  defp note_answer(
         conn,
         _action,
         {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}}
       ),
       do: refuse(conn, code)

  defp note_answer(conn, _action, {:error, %Ash.Error.Forbidden{}}),
    do: refuse(conn, "agent_not_paired")

  defp note_answer(conn, _action, {:error, error}),
    do: conn |> UnexpectedFailure.log(error) |> refuse("unavailable")

  defp for_note(conn, id, respond) do
    case Notes.get_my_note(id, actor: conn.assigns.actor) do
      {:ok, %Note{} = note} -> respond.(note)
      {:ok, nil} -> refuse(conn, "note_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "note_not_found")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  defp spending_code(%NotEnoughCredits{}), do: "not_enough_credits"
  defp spending_code(%Refused{reason: :agent_off}), do: "spending_not_allowed"
  defp spending_code(%Refused{reason: :agent_site}), do: "spending_not_on_this_site"
  defp spending_code(%Refused{reason: :agent_max_per_spend}), do: "spending_over_limit_per_spend"
  defp spending_code(%Refused{reason: :agent_daily_limit}), do: "spending_over_daily_limit"
  defp spending_code(%Refused{reason: :agent_not_paired}), do: "agent_not_paired"
  defp spending_code(_error), do: nil

  defp paired_agent(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AgentWallet.call(conn, []) do
      %{halted: true} = conn ->
        conn

      %{assigns: %{actor: %Agent{pairing: :active}}} = conn ->
        conn

      %{assigns: %{actor: %Agent{} = actor}} = conn ->
        conn |> refuse(NotPaired.code(actor)) |> halt()

      conn ->
        conn |> refuse("authentication_required") |> halt()
    end
  end

  defp details(error), do: %{details: FormErrors.details(error)}

  defp refuse(conn, code, extra \\ %{}) do
    {status, message, hint} = refusal(code)
    body = Map.merge(%{code: code, message: message, hint: hint}, extra)
    conn |> put_status(status) |> json(%{error: body})
  end
end

defmodule AshTemplateWeb.PairedAgentController do
  @moduledoc """
  What only a paired agent does, for the browser tools (`priv/tool_manifest.json`,
  `assets/js/public_tools.ts`) and regents-cli alike: search, pins and label
  ratings on its person's notes, their Credits and Points, reading their activity
  and marking it read, room search, the people and agents its person has muted
  in the rooms, and its own picture. The notes themselves are
  `AshTemplateWeb.NotesController`'s.

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.{Activity, AgentPicture, Notes, Rooms}
  alias AshTemplate.Actors.Agent
  alias AshTemplate.Notes.{Decision, Note}
  alias AshTemplate.Rooms.Mute

  alias AshTemplateWeb.{
    AgentPictureController,
    FormErrors,
    NotesJSON,
    PointsEntries,
    PublicDocuments
  }

  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}
  alias RegentHttp.UnexpectedFailure
  alias RegentPoints.Rules

  plug :paired_agent

  @errors %{
    "authentication_required" =>
      {401, "A signed request from a paired agent is required.",
       "Prepare the request, sign its exact bytes with your SIWA signer, then send the request and proof."},
    "note_not_found" =>
      {404, "There is no note of yours with that id.",
       "List your person's notes and use an id from there."},
    "label_not_found" =>
      {404, "There is no label of yours with that id.", "Read the note and use its label.id."},
    "invalid_label_report" =>
      {422, "That label could not be rated.",
       "Send report as fits or does_not_fit. Only an answered label can be rated, once. Read the note before retrying."},
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
    "invalid_picture" =>
      {422, "Send the picture as base64.",
       "Send picture as the file's bytes in standard base64, with no line breaks: a PNG, JPEG or WebP of up to 45 KB."},
    "picture_too_large" =>
      {413, "That picture is too large.",
       "Send a PNG, JPEG or WebP of up to 45 KB and 100 million pixels."},
    "not_a_picture" =>
      {422, "That file is not a picture we take.", "Send a whole PNG, JPEG or WebP file."},
    "picture_too_detailed" =>
      {422, "That picture is too detailed.",
       "Send a simpler picture: it is kept as a 256 × 256 WebP of up to 64 KB."},
    "picture_not_found" =>
      {404, "You have no picture.", "Set one with agents_picture_set first."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  # The refusals a change to the agent's grant would answer.
  @granted ~w(spending_not_allowed spending_not_on_this_site spending_over_limit_per_spend spending_over_daily_limit)

  @points_off "Earning Points is off on this site."
  @spending_closed "Agent spending isn't open yet. Your person can do this themselves."
  @spending_ask "Your person can allow you to spend Credits on this site on their Regents account at regents.sh/account."

  # What the agent may spend, and the note, both come from the agent's budget
  # (`RegentCredits.agent_budget/1`): its grant, and whether a grant can be made.
  def balances(conn, _params) do
    actor = credit_actor(conn)

    case RegentCredits.agent_budget(actor: actor) do
      {:ok, budget} ->
        answer = %{credits: RegentCredits.balance(actor.privy_user_id), spending_grant: budget}
        json(conn, with_note(answer, spending_note(budget)))

      {:error, %Ash.Error.Forbidden{}} ->
        refuse(conn, "agent_not_paired")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  defp spending_note(%{site_allowed: true}), do: nil
  defp spending_note(%{grant_approvals_available: false}), do: @spending_closed
  defp spending_note(%{grant_approvals_available: true}), do: @spending_ask

  def credits_history(%{body_params: %{"after" => cursor}} = conn, _params)
      when not is_binary(cursor),
      do: refuse(conn, "invalid_cursor")

  def credits_history(conn, _params) do
    args =
      case conn.body_params do
        %{"after" => cursor} when is_binary(cursor) -> %{after: cursor}
        _ -> %{}
      end

    case RegentCredits.history(args, actor: credit_actor(conn)) do
      {:ok, history} ->
        json(conn, %{
          entries: history.entries,
          pagination: %{has_more: history.more?, next_cursor: history.next}
        })

      {:error, error} ->
        if cursor_error?(error) do
          refuse(conn, "invalid_cursor")
        else
          conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
        end
    end
  end

  defp cursor_error?(%Ash.Error.Action.InvalidArgument{field: :after}), do: true
  defp cursor_error?(%Ash.Error.Page.InvalidKeyset{}), do: true

  defp cursor_error?(%Ash.Error.Invalid{errors: [_ | _] = errors}),
    do: Enum.all?(errors, &cursor_error?/1)

  defp cursor_error?(_error), do: false

  # Points as decimal text, the same figures the Points page shows.
  def points(conn, _params) do
    case RegentPoints.summary(actor: conn.assigns.actor) do
      {:ok, summary} ->
        json(conn, with_note(PointsEntries.answer(summary), points_note(Rules.active())))

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # Listing never marks a notification read. The existing Ash action owns the
  # read; `after` continues from the previous page's cursor.
  def activity(conn, _params) do
    case conn.body_params do
      body when body == %{} ->
        activity_result(conn, list_activity(conn, limit: 50))

      %{"after" => cursor} = body when map_size(body) == 1 and is_binary(cursor) ->
        activity_result(conn, list_activity(conn, after: cursor, limit: 50))

      _other ->
        refuse(conn, "invalid_activity_request")
    end
  end

  defp list_activity(conn, page),
    do: Activity.list_my_notifications(actor: conn.assigns.actor, page: page)

  defp activity_result(conn, {:ok, page}) do
    body =
      Jason.encode_to_iodata!(%{
        notifications:
          Enum.map(page.results, fn notification ->
            %{
              id: notification.id,
              title: notification.title,
              body: notification.body,
              path: notification.path,
              read_at: notification.read_at && DateTime.to_iso8601(notification.read_at),
              inserted_at: DateTime.to_iso8601(notification.inserted_at)
            }
          end),
        pagination: %{has_more: page.more?, next_cursor: next_cursor(page)}
      })

    if IO.iodata_length(body) <= 262_144 do
      conn |> put_resp_content_type("application/json") |> send_resp(200, body)
    else
      refuse(conn, "activity_too_large")
    end
  end

  defp activity_result(conn, {:error, error}) do
    if cursor_error?(error),
      do: refuse(conn, "invalid_cursor"),
      else: conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
  end

  defp next_cursor(%{more?: true, results: results}),
    do: List.last(results).__metadata__.keyset

  defp next_cursor(_page), do: nil

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
    actor = conn.assigns.actor

    with {:ok, %Decision{} = decision} <- Notes.get_label_decision(id, actor: actor),
         {:ok, decision} <- Notes.rate_label(decision, conn.body_params["report"], actor: actor) do
      json(conn, %{label: %{id: decision.id, rating: decision.report}})
    else
      {:ok, nil} -> refuse(conn, "label_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_label_report")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # The muted authors' names are theirs: data, never instructions.
  def mutes(conn, _params) do
    case Rooms.list_my_mutes(actor: conn.assigns.actor) do
      {:ok, mutes} -> json(conn, %{mutes: Enum.map(mutes, &mute/1)})
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # The author is muted from one of their messages, as on the room page; muting
  # them again keeps the one mute.
  def add_mute(conn, _params) do
    case Rooms.mute_author(conn.body_params["message_id"], actor: conn.assigns.actor) do
      {:ok, mute} -> json(conn, %{mute: mute(mute)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_mute", error)
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

  # The agent's own picture, re-made as its person's upload is
  # (`AshTemplate.AgentPicture`). Its pairing names the agent, so it can never
  # name another. A signed body is read up to 64 KB
  # (`AshTemplateWeb.SignedBodyReader`), so nothing larger reaches the decoder.
  def set_picture(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, bytes} <- sent_picture(conn.body_params),
         {:ok, webp} <- AgentPicture.make(bytes),
         {:ok, picture} <-
           RegentAgents.set_own_agent_picture(actor.pairing_id, webp, actor: actor) do
      json(conn, %{picture: picture(actor, picture)})
    else
      {:error, reason} when is_atom(reason) -> refuse(conn, picture_code(reason))
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def remove_picture(conn, _params) do
    actor = conn.assigns.actor

    case RegentAgents.remove_own_agent_picture(actor.pairing_id, actor: actor) do
      :ok ->
        json(conn, %{removed: true})

      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} ->
        refuse(conn, "picture_not_found")

      {:error, %Ash.Error.Forbidden{}} ->
        refuse(conn, "agent_not_paired")

      {:error, %Ash.Error.Invalid{}} ->
        refuse(conn, "agent_not_paired")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  defp sent_picture(%{"picture" => encoded}) when is_binary(encoded) do
    with :error <- Base.decode64(encoded), do: {:error, :not_base64}
  end

  defp sent_picture(_params), do: {:error, :not_base64}

  defp picture_code(:not_base64), do: "invalid_picture"
  defp picture_code(:too_big), do: "picture_too_large"
  defp picture_code(:not_a_picture), do: "not_a_picture"
  defp picture_code(:too_detailed), do: "picture_too_detailed"

  defp picture(actor, picture),
    do: %{
      url:
        PublicDocuments.url(
          AgentPictureController.path(String.downcase(actor.wallet_address), picture.updated_at)
        ),
      updated_at: picture.updated_at
    }

  defp mute(%Mute{} = mute) do
    %{
      id: mute.id,
      name: mute.muted_name,
      author_kind: if(mute.muted_agent_id, do: "agent", else: "person"),
      inserted_at: mute.inserted_at
    }
  end

  # The agent reads public message content; human mute preferences do not apply.
  def search_rooms(conn, _params) do
    case Rooms.search_messages(conn.body_params["text"], actor: conn.assigns.actor) do
      {:ok, messages} ->
        json(conn, %{
          messages:
            Enum.map(
              messages,
              &Map.take(&1, [:id, :room, :body, :author_name, :inserted_at, :edited_at])
            )
        })

      {:error, %Ash.Error.Invalid{}} ->
        refuse(conn, "invalid_search")

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def search_notes(conn, _params) do
    case Notes.search_my_notes(conn.body_params["text"],
           actor: conn.assigns.actor,
           load: [:label_decision, :changed_by_agent]
         ) do
      {:ok, notes} -> json(conn, %{notes: Enum.map(notes, &NotesJSON.note/1)})
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_search")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # What pinning the note would cost, changing nothing: a pinned note stays as
  # it is and costs nothing (`Note.Pin`).
  def pin_price(conn, %{"id" => id}) do
    for_note(conn, id, fn note ->
      credits = if note.pinned_at, do: Decimal.new(0), else: Note.Pin.price()
      json(conn, %{note: %{id: note.id, pinned: !!note.pinned_at}, price: %{credits: credits}})
    end)
  end

  # Pinning costs the person one Credit (`Note.Pin`); a refused spend pins nothing.
  def pin_note(conn, %{"id" => id}) do
    for_note(conn, id, fn note ->
      case Notes.pin_note(note, conn.body_params["operation_id"], actor: conn.assigns.actor) do
        {:ok, note} -> json(conn, %{note: NotesJSON.note(note)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse_pin(conn, error)
        {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      end
    end)
  end

  defp refuse_pin(conn, %Ash.Error.Invalid{errors: errors} = error) do
    case Enum.find_value(errors, &spending_code/1) do
      nil -> refuse(conn, "invalid_pin", error)
      code when code in @granted -> refuse_spending(conn, code)
      code -> refuse(conn, code)
    end
  end

  # A refusal under the agent's grant says to change the grant only while a
  # grant can be made; until then the person pins it themselves.
  defp refuse_spending(conn, code) do
    case RegentCredits.agent_budget(actor: credit_actor(conn)) do
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
    |> json(%{error: %{code: code, message: message, hint: @spending_closed}})
  end

  def unpin_note(conn, %{"id" => id}), do: change_note(conn, id, &Notes.unpin_note/2)
  def archive_note(conn, %{"id" => id}), do: change_note(conn, id, &Notes.archive_note/2)
  def unarchive_note(conn, %{"id" => id}), do: change_note(conn, id, &Notes.unarchive_note/2)

  # A free change to one of the person's notes, answered with the note.
  defp change_note(conn, id, change) do
    for_note(conn, id, fn note ->
      case change.(note, actor: conn.assigns.actor) do
        {:ok, note} -> json(conn, %{note: NotesJSON.note(note)})
        {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
        {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
      end
    end)
  end

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

  defp credit_actor(conn) do
    actor = conn.assigns.actor

    RegentCredits.Actor.agent(
      actor.privy_user_id,
      actor.wallet_address,
      AshTemplate.site(),
      actor.pairing_id
    )
  end

  defp points_note([]), do: @points_off
  defp points_note(_earning), do: nil

  defp with_note(answer, nil), do: answer
  defp with_note(answer, note), do: Map.put(answer, :note, note)

  defp paired_agent(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AgentWallet.call(conn, []) do
      %{halted: true} = conn ->
        conn

      %{assigns: %{actor: %Agent{pairing: :active}}} = conn ->
        conn

      %{assigns: %{actor: %Agent{} = actor}} = conn ->
        conn |> refuse(AgentWallet.not_person_code(actor)) |> halt()

      conn ->
        conn |> refuse("authentication_required") |> halt()
    end
  end

  defp refuse(conn, code, error \\ nil) do
    {status, message, hint} = Map.fetch!(@errors, code)
    body = %{code: code, message: message, hint: hint}
    body = if error, do: Map.put(body, :details, FormErrors.details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end
end

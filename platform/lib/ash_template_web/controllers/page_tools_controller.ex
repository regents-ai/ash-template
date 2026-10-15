defmodule AshTemplateWeb.PageToolsController do
  @moduledoc """
  The agent doors under `/tools` that the browser tools (`priv/tool_manifest.json`,
  `assets/js/public_tools.ts`) and regents-cli share: notes and the account's
  Credits and Points.

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.Actors.Agent
  alias AshTemplate.{Notes, Rooms}
  alias AshTemplate.Notes.{Decision, Note}
  alias AshTemplateWeb.{FormErrors, NotesJSON, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}
  alias RegentPoints.{Amount, Rules}

  plug :paired_agent

  @errors %{
    "authentication_required" =>
      {401, "A signed request from a paired agent is required.",
       "Prepare the request, sign its exact bytes with your SIWA signer, then send the request and proof."},
    "note_not_found" =>
      {404, "There is no note of yours with that id.",
       "List your person's notes and use an id from there."},
    "invalid_note" =>
      {422, "The note could not be saved.",
       "details says why. Send a title of 1 to 120 characters, an optional body of up to 10,000 characters, and operation_id, a UUID you keep when retrying."},
    "label_not_found" =>
      {404, "There is no label of yours with that id.", "Read the note and use its label.id."},
    "invalid_label_report" =>
      {422, "That label could not be rated.",
       "Send report as fits or does_not_fit. Only an answered label can be rated, once. Read the note before retrying."},
    "invalid_cursor" =>
      {422, "That history cursor is invalid.",
       "Send after as the previous page's pagination.next_cursor, unchanged, or omit it for the newest entries."},
    "invalid_search" =>
      {422, "The search could not be run.", "Send text of 2 to 100 characters."},
    "invalid_pin" =>
      {422, "The note could not be pinned.",
       "details says why. Send operation_id, a UUID you make for this pin and keep when retrying."},
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

  @points_off "Earning Points is off on this site."
  @spending_off "Approving agent spending is off on this site."

  def balances(conn, _params) do
    actor = credit_actor(conn)

    case RegentCredits.agent_budget(actor: actor) do
      {:ok, budget} ->
        answer = %{credits: RegentCredits.balance(actor.privy_user_id), spending_grant: budget}
        json(conn, with_note(answer, not RegentCredits.agent_grants_enabled?(), @spending_off))

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

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

  # Points as decimal text, as the Points page shows them.
  def points(conn, _params) do
    case RegentPoints.summary(actor: conn.assigns.actor) do
      {:ok, summary} ->
        answer = %{
          points: Amount.format(summary.balance_micro),
          earned_today: Amount.format(summary.earned_today_micro),
          pending: summary.pending,
          daily_allowances:
            Enum.map(
              summary.allowances,
              &%{scope: &1.scope, remaining: Amount.format(&1.remaining)}
            ),
          entries:
            Enum.map(
              summary.entries,
              &%{
                points: Amount.format(&1.points_micro_delta),
                source: &1.source_app,
                by: &1.actor_kind,
                earned_at: &1.earned_at
              }
            ),
          more: summary.more?
        }

        json(conn, with_note(answer, Rules.active() == [], @points_off))

      {:error, error} ->
        conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def notes(conn, _params) do
    case Notes.list_my_notes(actor: conn.assigns.actor) do
      {:ok, notes} -> json(conn, %{notes: Enum.map(notes, &NotesJSON.note/1)})
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  def note(conn, %{"id" => id}), do: for_note(conn, id, &json(conn, %{note: NotesJSON.note(&1)}))

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

  # A retry with the operation_id of a note already made answers that note (200).
  def create_note(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, nil} <- Notes.earlier_note(conn.body_params["operation_id"], actor: actor),
         {:ok, note} <- Notes.create_note(conn.body_params, actor: actor) do
      conn |> put_status(:created) |> json(%{note: NotesJSON.note(note)})
    else
      {:ok, %Note{} = earlier} -> json(conn, %{note: NotesJSON.note(earlier)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_note", error)
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
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
      code -> refuse(conn, code)
    end
  end

  def unpin_note(conn, %{"id" => id}) do
    for_note(conn, id, fn note ->
      case Notes.unpin_note(note, actor: conn.assigns.actor) do
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

  defp with_note(answer, true, note), do: Map.put(answer, :note, note)
  defp with_note(answer, false, _note), do: answer

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

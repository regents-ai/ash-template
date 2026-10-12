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
  alias AshTemplate.Notes
  alias AshTemplate.Notes.Note
  alias AshTemplateWeb.NotesJSON
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentCredits.Errors.{NotEnoughCredits, Refused}
  alias RegentPoints.{Amount, Rules}

  plug :paired_agent

  @errors %{
    "authentication_required" =>
      {401, "A signed request from a paired agent is required.",
       "Prepare the request, sign its exact bytes with your SIWA signer, then send the request and proof."},
    "agent_not_paired" =>
      {403, "This agent is not paired with an account.",
       "Ask your person to sign in at /account and choose you under Agents. Redeem the code they paste you at POST /api/agents/v1/pair (regents ash-template agents pair), then retry with fresh proof."},
    "person_not_here" =>
      {403, "The person this agent is paired with has no account on this site yet.",
       "Ask your person to sign in at /account on this site, then retry with fresh proof."},
    "note_not_found" =>
      {404, "There is no note of yours with that id.",
       "List your person's notes and use an id from there."},
    "invalid_note" =>
      {422, "The note could not be saved.",
       "details says why. Send a title of 1 to 120 characters, an optional body of up to 10,000 characters, and operation_id, a UUID you keep when retrying. If that operation_id was used before, the note exists: read it with notes_get."},
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

  @points_off "Earning Points is off on this site."
  @spending_off "Approving agent spending is off on this site."

  def balances(conn, _params) do
    actor = credit_actor(conn)

    case RegentCredits.agent_budget(actor: actor) do
      {:ok, budget} ->
        answer = %{credits: RegentCredits.balance(actor.privy_user_id), spending_grant: budget}
        json(conn, with_note(answer, not RegentCredits.agent_grants_enabled?(), @spending_off))

      {:error, _} ->
        refuse(conn, "unavailable")
    end
  end

  def credits_history(conn, _params) do
    args =
      case conn.body_params do
        %{"after" => cursor} when is_binary(cursor) -> %{after: cursor}
        _ -> %{}
      end

    case RegentCredits.history(args, actor: credit_actor(conn)) do
      {:ok, history} -> json(conn, history)
      {:error, _} -> refuse(conn, "unavailable")
    end
  end

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

      {:error, _} ->
        refuse(conn, "unavailable")
    end
  end

  def notes(conn, _params) do
    case Notes.list_my_notes(actor: conn.assigns.actor) do
      {:ok, notes} -> json(conn, %{notes: Enum.map(notes, &NotesJSON.note/1)})
      {:error, _error} -> refuse(conn, "unavailable")
    end
  end

  def note(conn, %{"id" => id}), do: for_note(conn, id, &json(conn, %{note: NotesJSON.note(&1)}))

  def search_notes(conn, _params) do
    case Notes.search_my_notes(conn.body_params["text"],
           actor: conn.assigns.actor,
           load: [:label_decision, :changed_by_agent]
         ) do
      {:ok, notes} -> json(conn, %{notes: Enum.map(notes, &NotesJSON.note/1)})
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_search")
      {:error, _error} -> refuse(conn, "unavailable")
    end
  end

  def create_note(conn, _params) do
    case Notes.create_note(conn.body_params, actor: conn.assigns.actor) do
      {:ok, note} -> conn |> put_status(:created) |> json(%{note: NotesJSON.note(note)})
      {:error, %Ash.Error.Invalid{} = error} -> refuse(conn, "invalid_note", error)
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, _error} -> refuse(conn, "unavailable")
    end
  end

  # Pinning costs the person one Credit (`Note.Pin`); a refused spend pins nothing.
  def pin_note(conn, %{"id" => id}) do
    for_note(conn, id, fn note ->
      case Notes.pin_note(note, conn.body_params["operation_id"], actor: conn.assigns.actor) do
        {:ok, note} -> json(conn, %{note: NotesJSON.note(note)})
        {:error, %Ash.Error.Invalid{} = error} -> refuse_pin(conn, error)
        {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
        {:error, _error} -> refuse(conn, "unavailable")
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
        {:error, _error} -> refuse(conn, "unavailable")
      end
    end)
  end

  defp for_note(conn, id, respond) do
    case Notes.get_my_note(id, actor: conn.assigns.actor) do
      {:ok, %Note{} = note} -> respond.(note)
      {:ok, nil} -> refuse(conn, "note_not_found")
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "note_not_found")
      {:error, %Ash.Error.Forbidden{}} -> refuse(conn, "agent_not_paired")
      {:error, _error} -> refuse(conn, "unavailable")
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
      AshTemplate.Credits.site(),
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
    body = if error, do: Map.put(body, :details, details(error)), else: body
    conn |> put_status(status) |> json(%{error: body})
  end

  # Each refused field and why, worded as the page's own form shows it.
  defp details(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.filter(&AshPhoenix.FormData.Error.impl_for/1)
    |> Enum.flat_map(&List.wrap(AshPhoenix.FormData.Error.to_form_error(&1)))
    |> Enum.map(fn {field, message, vars} ->
      %{field: field, message: Enum.reduce(vars, message, &interpolate/2)}
    end)
  end

  defp interpolate({key, value}, message),
    do: String.replace(message, "%{#{key}}", fn _placeholder -> to_string(value) end)
end

defmodule AshTemplateWeb.PairedAgentController do
  @moduledoc """
  What only a paired agent does, for the browser tools (`priv/tool_manifest.json`,
  `assets/js/public_tools.ts`) and regents-cli alike: search, pins and label
  ratings on its person's notes, their Credits and Points, reading their activity
  and marking it read, room search, and the people and agents its person has
  muted in the rooms. The notes themselves are `AshTemplateWeb.NotesController`'s.

  Every request needs per-request SIWA proof from an actively paired agent.
  Browser cookies grant no authority.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.{Activity, Notes, Rooms}
  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Notes.{Decision, Note}
  alias AshTemplate.Payments.NotePin
  alias AshTemplate.Rooms.Mute
  alias AshTemplateWeb.{FormErrors, NotesJSON, PointsEntries, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentPayments.{Purchase, USDC}
  alias RegentPoints.Rules

  require AgentWallet

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
    "invalid_pin" => {422, "The note could not be pinned.", "details says why."},
    "person_needs_sign_in" =>
      {403, "Your person needs to sign in on this site again before you can pay for them.",
       "Ask your person to sign in on this site once, then ask again."},
    "owner_pins_not_open" =>
      {403, "Pins are not open yet on an account an agent opened.",
       "Nothing was charged. Pins are paid for by an agent a person paired with their account."},
    "pins_not_set_up" =>
      {503, "Paid pins are not set up on this site yet.",
       "Nothing was charged. Try again once this site has set them up."},
    "pin_settled" =>
      {202, "The pin is paid for and is being applied.",
       "Ask again the same way to finish it. You will not pay twice."},
    "settlement_pending" =>
      {409, "This purchase is waiting on a check of its payment.",
       "Do not pay again. Ask again later the same way to see where it stands."},
    "terms_expired" =>
      {410, "Those payment terms are no longer on offer.",
       "Ask again without a payment to be given fresh terms."},
    "payment_service_unavailable" =>
      {502, "The payment service could not be reached.",
       "Do not pay again. Ask again with the same payment."},
    "unavailable" => {503, "That could not be reached right now.", "Try again in a moment."}
  }
  @errors Map.merge(@errors, AgentWallet.not_person_refusals())

  @points_off "Earning Points is off on this site."
  @spending_closed "Agent spending isn't open yet. Your person can do this themselves."
  @spending_ask "Your person can allow you to spend Credits on this site on their Regents account at regents.sh/account."
  @pay_hint ~s(Sign the payment terms with your own wallet and send the signed payment as "payment" in the body, or send {"pay_with": "credits"} to pay with your person's Credits. Asking again the same way never pays twice.)

  # An agent that owns its account spends as its owner, under no grant.
  def balances(%{assigns: %{actor: %Human{} = owner}} = conn, _params),
    do: json(conn, %{credits: RegentCredits.balance(owner.privy_user_id), spending_grant: nil})

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
  # it is and costs nothing. An account's owner has no pins yet.
  def pin_price(%{assigns: %{actor: %Human{}}} = conn, _params),
    do: refuse(conn, "owner_pins_not_open")

  def pin_price(conn, %{"id" => id}) do
    for_note(conn, id, fn note ->
      price = if note.pinned_at, do: 0, else: NotePin.price_atomic()

      json(conn, %{
        note: %{id: note.id, pinned: !!note.pinned_at},
        price: %{usdc: USDC.format(price), credits: USDC.format(price)}
      })
    end)
  end

  @doc """
  Pins the note once its pin is paid for (`AshTemplate.Payments.NotePin`): 1 USDC
  from the agent's own wallet, an x402 payment sent as `"payment"` in the signed
  body, or 1 of its person's Credits when the body says `"pay_with": "credits"`.
  Without either it answers 402 with the terms. Asked again for the same note,
  it pays the terms it already offered, so a retry never pays twice. A note
  already pinned costs nothing. An agent that owns its account has no pins yet:
  the payment is for a person, made by the agent they paired.
  """
  def pin_note(%{assigns: %{actor: %Human{}}} = conn, _params),
    do: refuse(conn, "owner_pins_not_open")

  def pin_note(conn, %{"id" => id}) do
    for_note(conn, id, fn
      %{pinned_at: %DateTime{}} = note -> json(conn, %{note: NotesJSON.note(note)})
      note -> pay_for_pin(conn, note)
    end)
  end

  defp pay_for_pin(%{assigns: %{actor: %Agent{beneficiary_profile_id: nil}}} = conn, _note),
    do: refuse(conn, "person_needs_sign_in")

  defp pay_for_pin(conn, note) do
    actor = conn.assigns.actor

    with :ok <- payments_set_up(),
         {:ok, {:terms, intent}} <- pin_terms(actor, note.id) do
      conn |> pay(actor, intent) |> answer_pin(conn)
    else
      {:ok, {:pinned, note}} -> json(conn, %{note: NotesJSON.note(note)})
      :not_set_up -> refuse(conn, "pins_not_set_up")
      {:error, :note_gone} -> refuse(conn, "note_not_found")
      {:error, error} -> refuse_payment(conn, error)
    end
  end

  defp payments_set_up, do: if(NotePin.pay_to(), do: :ok, else: :not_set_up)

  # Chosen under the note's row lock, so requests at once agree on one set of
  # terms and see a pin paid meanwhile. Terms already offered for this note and
  # not yet used are paid again, so a retry pays once; a pin paid earlier and
  # since unpinned starts afresh.
  defp pin_terms(actor, note_id) do
    Ash.transact([Note, RegentPayments.PaymentIntent], fn ->
      case Notes.lock_my_note(note_id, actor: actor) do
        {:ok, %Note{pinned_at: %DateTime{}}} ->
          {:pinned, Notes.get_my_note!(note_id, actor: actor)}

        {:ok, %Note{}} ->
          terms(actor, note_id)

        {:ok, nil} ->
          {:error, :note_gone}

        {:error, error} ->
          {:error, error}
      end
    end)
  end

  defp terms(actor, note_id) do
    case Purchase.on_offer(NotePin, actor, &(&1.target_id == note_id and &1.status != :applied)) do
      nil ->
        with {:ok, intent} <- Purchase.prepare(NotePin, %{note_id: note_id}, actor),
             do: {:terms, intent}

      intent ->
        {:terms, intent}
    end
  end

  defp pay(%{body_params: %{"pay_with" => "credits"}} = conn, actor, intent),
    do: Purchase.pay_with_credits(actor, intent.id, credit_actor(conn), %{})

  defp pay(conn, actor, intent),
    do: Purchase.execute(actor, intent.id, %{payment: payment(conn), payer: nil, context: %{}})

  # The x402 payment travels in the signed body, so the agent's proof covers it.
  defp payment(%{body_params: %{"payment" => payment}}) when is_binary(payment) and payment != "",
    do: payment

  defp payment(_conn), do: nil

  defp answer_pin({:applied, intent, receipt}, conn) do
    for_note(conn, intent.target_id, fn note ->
      conn
      |> paid_header(receipt)
      |> json(%{
        note: NotesJSON.note(note),
        payment_intent_id: intent.id,
        receipt: Purchase.receipt_payload(receipt)
      })
    end)
  end

  defp answer_pin({:payment_required, intent}, conn), do: ask_payment(conn, intent, nil)

  defp answer_pin({:payment_rejected, intent, reason}, conn),
    do: ask_payment(conn, intent, reason)

  defp answer_pin({:credits_refused, intent, words}, conn) do
    conn
    |> put_status(402)
    |> json(%{
      error: %{
        code: "credits_refused",
        message: words,
        hint:
          "Nothing was spent. account_balances shows your person's Credits and the limits they set for you. You can pay in USDC instead."
      },
      payment_intent_id: intent.id
    })
  end

  defp answer_pin({:settled, intent, _receipt}, conn),
    do: refuse_intent(conn, "pin_settled", intent)

  defp answer_pin({:settlement_pending, intent}, conn),
    do: refuse_intent(conn, "settlement_pending", intent)

  defp answer_pin({:expired, intent}, conn), do: refuse_intent(conn, "terms_expired", intent)

  defp answer_pin({:facilitator_unavailable, intent, _reason}, conn),
    do: refuse_intent(conn, "payment_service_unavailable", intent)

  defp answer_pin({:error, error}, conn), do: refuse_payment(conn, error)

  defp ask_payment(conn, intent, reason) do
    price = USDC.format(intent.amount_atomic)

    message =
      reason || "Pinning this note costs #{price} USDC, or #{price} of your person's Credits."

    terms = Purchase.terms(intent, message, url(~p"/api/v1/notes/#{intent.target_id}/pin"))
    {:ok, header} = X402.PaymentRequired.encode(terms)

    conn
    |> put_resp_header("payment-required", header)
    |> put_status(402)
    |> json(%{
      error: %{code: "payment_required", message: message, hint: @pay_hint},
      payment_intent_id: intent.id,
      price: %{usdc: price, credits: price},
      payment_terms: terms
    })
  end

  defp paid_header(conn, %{paid_with: :usdc, payment_response: response}) do
    {:ok, header} = X402.PaymentResponse.encode(response)
    put_resp_header(conn, "payment-response", header)
  end

  defp paid_header(conn, _paid_with_credits), do: conn

  defp refuse_payment(conn, %Ash.Error.Forbidden{}), do: refuse(conn, "agent_not_paired")
  defp refuse_payment(conn, %Ash.Error.Invalid{} = error), do: refuse(conn, "invalid_pin", error)

  defp refuse_payment(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("unavailable")

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

  defp credit_actor(%{assigns: %{actor: %Human{} = owner}}),
    do:
      RegentCredits.Actor.person(owner.privy_user_id, owner.wallet_addresses, AshTemplate.site())

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

      %{assigns: %{actor: actor}} = conn when AgentWallet.acts_for_account(actor) ->
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

  defp refuse_intent(conn, code, intent) do
    {status, message, hint} = Map.fetch!(@errors, code)

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, hint: hint}, payment_intent_id: intent.id})
  end
end

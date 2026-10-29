defmodule AshTemplateWeb.PairedAgentController do
  @moduledoc """
  What only a paired agent does, for the browser tools (`priv/tool_manifest.json`,
  `assets/js/public_tools.ts`) and regents-cli alike: search, pins and label
  ratings on its person's notes, their Credits and Points, reading their activity
  and marking it read, room search, and the people and agents its person has
  muted in the rooms. The notes themselves are `AshTemplateWeb.NotesController`'s,
  which also holds the words of every notes refusal; the words of a mute's
  refusals are `AshTemplateWeb.RoomsController`'s.

  Every request needs per-request SIWA proof from an actively paired agent, or
  from an agent that owns its account, which acts as that account. Browser
  cookies grant no authority.
  """

  use AshTemplateWeb, :controller

  alias AshTemplate.{Accounts, Activity, Notes, Rooms}
  alias AshTemplate.Accounts.Holdings
  alias AshTemplate.Activity.Refused, as: ActivityRefused
  alias AshTemplate.Actors.{Agent, Human}
  alias AshTemplate.Agents.NotPaired
  alias AshTemplate.Notes.Note
  alias AshTemplate.Payments.NotePin
  alias AshTemplateWeb.{FormErrors, NotesController, RoomsController, UnexpectedFailure}
  alias AshTemplateWeb.Plugs.AgentWallet
  alias RegentPayments.{Purchase, USDC}

  require AgentWallet

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
    "invalid_search" =>
      {422, "The search could not be run.", "Send text of 2 to 100 characters."},
    "invalid_pin" => {422, "The note could not be pinned.", "details says why."},
    "person_needs_sign_in" =>
      {403, "Your person needs to sign in on this site again before you can pay for them.",
       "Ask your person to sign in on this site once, then ask again."},
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

  @notes ~w(note_not_found label_not_found invalid_label_report owner_pins_not_open)
  @mutes ~w(mute_not_found invalid_mute)

  @doc """
  The `{status, message, hint}` of the refusal `code`, for the hosted MCP
  server's tool errors (`AshTemplateWeb.ToolErrors`); a notes refusal is in the
  notes' own words, and a mute's in the rooms'.
  """
  def refusal(code) when code in @notes, do: NotesController.refusal(code)
  def refusal(code) when code in @mutes, do: RoomsController.refusal(code)
  def refusal(code), do: Map.fetch!(@errors, code)

  @pay_hint ~s(Sign the payment terms with your own wallet and send the signed payment as "payment" in the body, or send {"pay_with": "credits"} to pay with your person's Credits. Asking again the same way never pays twice.)
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
  # /app/activity does. It takes no input: any is refused, and a body that is not
  # an object, which Phoenix hands on as `_json` and Ash skips, never reaches it.
  def mark_activity_read(%{body_params: %{"_json" => _body}} = conn, _params),
    do: refuse(conn, "invalid_mark_read_request")

  def mark_activity_read(conn, _params) do
    case Activity.activity_mark_read(conn.body_params, actor: conn.assigns.actor) do
      {:ok, marked} -> json(conn, marked)
      {:error, %Ash.Error.Invalid{}} -> refuse(conn, "invalid_mark_read_request")
      # The pairing was revoked after this request was let in.
      {:error, %Ash.Error.Forbidden{errors: [%NotPaired{code: code}]}} -> refuse(conn, code)
      {:error, error} -> conn |> UnexpectedFailure.log(error) |> refuse("unavailable")
    end
  end

  # The address names the label: an id in the body never chooses another.
  def report_label(conn, %{"id" => id}) do
    note_answer(
      conn,
      :notes_rate_label,
      Notes.notes_rate_label(id, Map.delete(conn.body_params, "id"), actor: conn.assigns.actor)
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
  def add_mute(conn, _params),
    do:
      RoomsController.respond(
        conn,
        :mutes_add,
        Rooms.mutes_add(conn.body_params, actor: conn.assigns.actor)
      )

  def remove_mute(conn, %{"id" => id}),
    do:
      RoomsController.respond(
        conn,
        :mutes_remove,
        Rooms.mutes_remove(id, actor: conn.assigns.actor)
      )

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
      %{pinned_at: %DateTime{}} = note -> json(conn, %{note: Note.present(note)})
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
      {:ok, {:pinned, note}} -> json(conn, %{note: Note.present(note)})
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
    do:
      Purchase.pay_with_credits(actor, intent.id, Holdings.credit_actor(conn.assigns.actor), %{})

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
        note: Note.present(note),
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

  defp refuse_payment(conn, %Ash.Error.Invalid{} = error),
    do: refuse(conn, "invalid_pin", details(error))

  defp refuse_payment(conn, error),
    do: conn |> UnexpectedFailure.log(error) |> refuse("unavailable")

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

  defp paired_agent(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case AgentWallet.call(conn, []) do
      %{halted: true} = conn ->
        conn

      %{assigns: %{actor: actor}} = conn when AgentWallet.acts_for_account(actor) ->
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

  defp refuse_intent(conn, code, intent) do
    {status, message, hint} = Map.fetch!(@errors, code)

    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, hint: hint}, payment_intent_id: intent.id})
  end
end

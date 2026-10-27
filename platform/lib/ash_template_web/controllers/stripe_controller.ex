defmodule AshTemplateWeb.StripeController do
  @moduledoc """
  Stripe's notices about card and Link purchases of Credits, at
  `POST /api/stripe/notices`. The exact body, kept by
  `AshTemplateWeb.SignedBodyReader`, and its `Stripe-Signature` header go to
  `RegentCredits.card_notice/3`, which adds a paid purchase's Credits once and
  takes them back on a refund or dispute. Stripe sends a notice again until it
  is answered 200, so a notice that could not be handled is answered 500.
  """
  use AshTemplateWeb, :controller

  alias RegentCredits.Errors.Refused

  def notice(conn, _params) do
    with true <- RegentCredits.card_payments?(),
         [signature] <- get_req_header(conn, "stripe-signature"),
         :ok <-
           RegentCredits.card_notice(conn.assigns.raw_body, signature,
             actor: AshTemplate.Credits.site_actor()
           ) do
      json(conn, %{received: true})
    else
      false ->
        refuse(conn, :not_found, "not_found", "This site takes no card payments.")

      {:error, %Ash.Error.Invalid{errors: [%Refused{reason: :not_from_stripe}]}} ->
        refuse(conn, :bad_request, "not_from_stripe", "The signature does not match.")

      {:error, _error} ->
        refuse(conn, :internal_server_error, "not_handled", "Send the notice again.")

      _no_signature ->
        refuse(conn, :bad_request, "not_from_stripe", "The Stripe-Signature header is missing.")
    end
  end

  defp refuse(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end

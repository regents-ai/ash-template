defmodule AshTemplateWeb.SiwaSessionController do
  @moduledoc """
  The SIWA pages' sign-in at the sign-in service. The browser's sign-in bridge
  posts the person's Privy pair here, with the session cookie and the forms
  token the browser pipeline checks, and this trades it for a control token
  (`AshTemplate.SiwaControl.session/1`). The token stays on this machine, kept
  for this browser's sign-in (`AshTemplate.SiwaControl.Tokens`), and only while
  the person the service proved is the person signed in here. The answer says
  only whether it worked: 204, or a refusal in the site's own words.
  """
  use AshTemplateWeb, :controller

  alias AshTemplate.Accounts.{RequestRateLimiter, SessionAuthority}
  alias AshTemplate.SiwaControl
  alias AshTemplate.SiwaControl.{Refusal, Tokens}

  require Logger

  # A page trades at most once for each thing a person does, and a token lasts
  # fifteen minutes, so this is far above what any person's pages need.
  @limit 30
  @window_seconds 60

  @refusals %{
    "authentication_required" => {401, "Sign in to use SIWA.", "Sign in, then try again."},
    "siwa_sign_in_refused" => {401, "SIWA couldn't confirm your sign-in.", "Sign in again."},
    "rate_limited" =>
      {429, "Too many tries in a short time.",
       "Wait the number of seconds in Retry-After, then try again."},
    "siwa_unavailable" => {503, "SIWA isn't available right now.", "Try again in a moment."}
  }

  def create(%{assigns: %{current_human_account: nil}} = conn, _untrusted_params),
    do: refuse(conn, "authentication_required")

  def create(%{assigns: %{current_human_account: account}} = conn, _untrusted_params) do
    case RequestRateLimiter.admit({:siwa_session, account.id}, @limit, @window_seconds) do
      {:ok, _budget} -> trade(conn, account)
      {:error, :rate_limited, _budget} -> limited(conn, :site)
    end
  end

  defp trade(conn, account) do
    topic = SessionAuthority.topic(conn.assigns.current_lineage)

    with {:ok, pair} <- RegentPrivy.Proof.pair(conn),
         {:ok, session} <- SiwaControl.session(pair),
         {:ok, token, expires_at} <- for_person(session, account),
         :ok <- Tokens.keep(topic, account.id, token, expires_at) do
      conn |> put_resp_header("cache-control", "no-store") |> send_resp(:no_content, "")
    else
      {:error, {:request_pair, _missing}} -> refused(conn, :missing_pair)
      {:error, %Refusal{status: 401, code: "privy_proof_invalid"}} -> refused(conn, :privy_proof)
      {:error, :another_person} -> refused(conn, :another_person)
      {:error, %Refusal{status: 429, code: "rate_limited"}} -> limited(conn, :siwa)
      {:error, reason} -> unavailable(conn, reason)
    end
  end

  # The token counts only for the person signed in here, and only with the time
  # it ends.
  defp for_person(%{"token" => token, "expiresAt" => at, "did" => did}, %{privy_user_id: did})
       when is_binary(token) and is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, expires_at, _offset} -> {:ok, token, expires_at}
      {:error, _unreadable} -> {:error, :unreadable}
    end
  end

  defp for_person(%{"did" => did}, _account) when is_binary(did), do: {:error, :another_person}
  defp for_person(_session, _account), do: {:error, :unreadable}

  # Each reason is a fixed atom, never a token or the service's words.
  defp refused(conn, reason) do
    Logger.info("SIWA control sign-in refused reason=#{reason}")
    refuse(conn, "siwa_sign_in_refused")
  end

  # Too many trades, counted here or by SIWA, whose own count is per minute too.
  defp limited(conn, by) do
    Logger.info("SIWA control sign-in limited by=#{by}")

    conn
    |> put_resp_header("retry-after", to_string(@window_seconds))
    |> refuse("rate_limited")
  end

  defp unavailable(conn, %Refusal{status: status, code: code}) do
    Logger.warning("SIWA control sign-in unavailable status=#{status} code=#{inspect(code)}")
    refuse(conn, "siwa_unavailable")
  end

  defp unavailable(conn, reason) when is_atom(reason) do
    Logger.warning("SIWA control sign-in unavailable reason=#{reason}")
    refuse(conn, "siwa_unavailable")
  end

  defp refuse(conn, code) do
    {status, message, hint} = Map.fetch!(@refusals, code)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end

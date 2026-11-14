defmodule AshTemplate.SiwaControl.Tokens do
  @moduledoc """
  The control token each signed-in browser traded for at the sign-in service
  (`AshTemplate.SiwaControl.session/1`), kept in this machine's memory with the
  account it was traded for, by the browser's sign-in here: its session topic
  (`AshTemplate.Accounts.SessionAuthority.topic/1`), which names the sign-in
  without being able to act as it. A token leaves when the service says it ends,
  when that sign-in ends or moves to another account
  (`AshTemplateWeb.PrivySessionController`), or with a collected generation; the
  page then trades again. Nothing else holds it: not the page, the browser, a log
  or an error.
  """
  use Nebulex.Cache, otp_app: :ash_template, adapter: Nebulex.Adapters.Local

  @doc """
  Keeps `token` for the sign-in `topic` and `account_id` until `expires_at`;
  one that has already ended is not kept.
  """
  @spec keep(String.t(), term(), String.t(), DateTime.t()) :: :ok | {:error, :ended}
  def keep(topic, account_id, token, expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :millisecond) do
      ttl when ttl > 0 -> put!(topic, {account_id, token}, ttl: ttl)
      _ended -> {:error, :ended}
    end
  end

  @doc "The token kept for the sign-in `topic`, when it was traded for `account_id`."
  @spec token(String.t(), term()) :: {:ok, String.t()} | :error
  def token(topic, account_id) do
    case get!(topic) do
      {^account_id, token} -> {:ok, token}
      _none_or_another -> :error
    end
  end

  @doc "Forgets the token kept for the sign-in `topic`, if any."
  @spec forget(String.t() | nil) :: :ok
  def forget(nil), do: :ok
  def forget(topic), do: delete!(topic)
end

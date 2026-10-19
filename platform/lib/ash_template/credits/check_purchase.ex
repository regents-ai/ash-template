defmodule AshTemplate.Credits.CheckPurchase do
  @moduledoc """
  Follows one Buy a person sent from the Buy Credits panel until it counts:
  reports it as a purchase once the chain holds it, then checks it until it is
  credited or fails. Crediting is the library's own purchase path
  (`RegentCredits.report_purchase/7`, `RegentCredits.check_purchase/2`), which
  credits a purchase once however often it is reported or checked.

  The job snoozes two seconds between tries, for up to five minutes, one job per
  purchase at a time. It tells the panel what happened on the person's purchase
  topic (`topic/1`): credited or failed, not recorded, or still checking when it
  stops. A Buy still checking then is credited by the Regents site's own reads of
  every Credits deposit on Base, open page or not.
  """

  use Oban.Worker,
    queue: :purchase_checks,
    max_attempts: 5,
    unique: [
      keys: [:privy_user_id, :signer, :tx_hash],
      period: :infinity,
      states: :incomplete
    ]

  alias AshTemplate.{Credits, Limits}
  alias RegentCredits.Errors.Refused

  @wait_seconds 2
  @tries 150

  @doc "Where the panel hears how this person's purchases ended."
  def topic(privy_user_id), do: "credits_purchases:" <> privy_user_id

  @doc """
  Queues the check of a sent Buy for `account` (its id, `privy_user_id` and
  the wallets its sign-in verified), paid by `signer`.
  """
  def start(account, signer, dollars, number, hash) do
    %{
      account_id: account.id,
      privy_user_id: account.privy_user_id,
      wallets: account.wallet_addresses,
      signer: signer,
      dollars: dollars,
      number: number,
      tx_hash: hash
    }
    |> new()
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: args, meta: meta}) do
    tries = Map.get(meta, "snoozed", 0)

    case report(args) do
      {:ok, %{status: :checking} = purchase} -> check(args, purchase, tries)
      {:ok, purchase} -> tell(args, %{purchase: purchase, stalled?: false})
      :again when tries < @tries -> {:snooze, @wait_seconds}
      :again -> tell(args, %{purchase: nil, stalled?: false})
      {:error, _refused} -> tell(args, %{purchase: nil, stalled?: false})
    end
  end

  # Reporting the same purchase again answers with it, so every try reports.
  # Reported again: past the person's report allowance, before the chain holds
  # the Buy, or when the chain could not be read. Any other refusal is final.
  defp report(args) do
    with :ok <- Limits.spend(:credits_report, {:human, args["account_id"]}),
         {:error, error} <-
           RegentCredits.report_purchase(
             args["privy_user_id"],
             args["signer"],
             :base,
             args["dollars"],
             args["number"],
             args["tx_hash"],
             actor: actor(args)
           ) do
      if again?(error), do: :again, else: {:error, error}
    else
      :limited -> :again
      {:ok, purchase} -> {:ok, purchase}
    end
  end

  defp again?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &match?(%Refused{reason: :not_seen_yet}, &1))

  defp again?(%Ash.Error.Unknown{}), do: true
  defp again?(_refused), do: false

  defp check(args, purchase, tries) do
    case RegentCredits.check_purchase(purchase.id, actor: actor(args)) do
      {:ok, %{status: :checking} = purchase} when tries >= @tries ->
        tell(args, %{purchase: purchase, stalled?: true})

      {:ok, %{status: :checking}} ->
        {:snooze, @wait_seconds}

      {:ok, purchase} ->
        tell(args, %{purchase: purchase, stalled?: false})

      {:error, _unread} when tries < @tries ->
        {:snooze, @wait_seconds}

      {:error, _unread} ->
        tell(args, %{purchase: purchase, stalled?: true})
    end
  end

  defp tell(args, shown) do
    Phoenix.PubSub.broadcast(
      AshTemplate.PubSub,
      topic(args["privy_user_id"]),
      {:credits_purchase, args["tx_hash"], shown}
    )
  end

  defp actor(args),
    do: Credits.person(%{privy_user_id: args["privy_user_id"], wallet_addresses: args["wallets"]})
end

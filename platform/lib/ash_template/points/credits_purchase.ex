defmodule AshTemplate.Points.CreditsPurchase do
  @moduledoc """
  Regent Points' check of a Credits purchase, in USDC or by card or Link: it
  reads the saved purchase and answers with what Points records. Only a
  credited purchase counts, for the account whose sign-in owns it, and a card
  purchase only when real money paid for it: Stripe's test keys add Credits for
  testing, not Points.
  """

  require Ash.Query

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.System

  def verify(%{"source_kind" => "credits_purchase", "source_event_key" => id}) do
    query = Ash.Query.filter(RegentCredits.Purchase, id == ^id)

    # No person is asking: Points' server check reads the committed purchase it was given.
    case RegentCredits.purchases!(query: query, authorize?: false) do
      [%{status: :credited} = purchase] -> with_account(purchase, &usdc_facts/2)
      [] -> {:error, :purchase_not_found}
      [_purchase] -> {:error, :purchase_not_credited}
    end
  end

  def verify(%{"source_kind" => "card_purchase", "source_event_key" => id}) do
    query = Ash.Query.filter(RegentCredits.CardPurchase, id == ^id)

    # As above: the server check reads the committed card purchase it was given.
    case RegentCredits.card_purchases!(query: query, authorize?: false) do
      [%{status: :credited, livemode: true} = purchase] -> with_account(purchase, &card_facts/2)
      [%{status: :credited}] -> {:error, :card_test_payment}
      [] -> {:error, :purchase_not_found}
      [_purchase] -> {:error, :purchase_not_credited}
    end
  end

  defp with_account(purchase, facts) do
    case Accounts.get_by_privy_did(purchase.privy_user_id, actor: %System{}) do
      {:ok, %{} = account} -> {:ok, facts.(purchase, account)}
      {:ok, nil} -> {:error, :purchase_account_not_found}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp usdc_facts(purchase, account) do
    purchase
    |> facts(account, "credits_purchase")
    |> Map.put(:evidence, %{
      "purchased_usdc_atomic" => RegentCredits.Chains.micro(purchase.amount),
      "chain" => to_string(purchase.chain),
      "tx_hash" => purchase.tx_hash
    })
  end

  # A Credit costs one US dollar however it is paid, so the card fee on top earns nothing.
  defp card_facts(purchase, account) do
    purchase
    |> facts(account, "card_purchase")
    |> Map.put(:evidence, %{
      "purchased_usdc_atomic" => RegentCredits.Chains.micro(Decimal.new(purchase.credits)),
      "payment_intent_id" => purchase.payment_intent_id
    })
  end

  defp facts(purchase, account, kind) do
    %{
      # The same source as AshTemplate.Points.Award: Credits is one Regents ledger on every site.
      source_app: "regents",
      source_kind: kind,
      source_event_key: purchase.id,
      account_id: account.id,
      actor_kind: "human",
      actor_id: to_string(account.id),
      source_action_at: purchase.inserted_at,
      qualified_at: purchase.credited_at,
      evidence_ref: kind <> ":" <> purchase.id
    }
  end
end

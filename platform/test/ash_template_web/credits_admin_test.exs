defmodule AshTemplateWeb.CreditsAdminTest do
  # A refund is matched to its purchase to the millionth on chain, so what the
  # admin is asked to lock and send stays as exact as the deposit that landed,
  # while the purchase row reads the shared way.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  @admin "did:privy:credits-admin-test"
  @person "did:privy:credits-admin-test-buyer"

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo)
    settings = Application.fetch_env!(:regent_credits, :admins)
    Application.put_env(:regent_credits, :admins, [@admin])

    on_exit(fn ->
      Application.put_env(:regent_credits, :admins, settings)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "a refund of an uneven deposit asks for the exact amount" do
    {:ok, purchase} =
      RegentCredits.Purchase
      |> Ash.Changeset.for_create(
        :record,
        %{
          privy_user_id: @person,
          wallet: "0x" <> String.duplicate("c", 40),
          chain: :base,
          amount: Decimal.new("4.123456"),
          number: Ecto.UUID.generate(),
          tx_hash: "0x" <> String.duplicate("2", 64)
        },
        authorize?: false
      )
      |> Ash.create()

    {:ok, _credited} =
      RegentCredits.Purchase
      |> Ash.ActionInput.for_action(:credit, %{id: purchase.id}, authorize?: false)
      |> Ash.run_action()

    admin = %{privy_user_id: @admin}
    {:ok, _refund} = RegentCredits.start_refund(purchase.id, actor: AshTemplate.Credits.admin(admin))

    html =
      render_component(AshTemplateWeb.CreditsAdmin, id: "credits-admin", lease: nil, account: admin)

    assert html =~ "Send exactly <strong>4.123456 USDC</strong>"
  end
end

defmodule AshTemplate.AccountsPolicyTest do
  use AshTemplateWeb.ConnCase, async: false

  alias AshTemplate.Accounts
  alias AshTemplate.Actors.{Human, System}

  @did "did:privy:policy-matrix"

  test "verified identity actions require the exact system actor" do
    assert {:ok, account} = Accounts.register_verified(@did, nil, [], actor: %System{})

    for actor <- [nil, %Human{human_account_id: account.id}, %{role: :system}, %{rail: :agent}] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.get_by_privy_did(@did, actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.register_verified("#{@did}:#{inspect(actor)}", nil, [], actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.refresh_verified(account, nil, [], actor: actor)
    end
  end
end

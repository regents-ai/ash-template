defmodule AshTemplate.Notes.WebhookFailureTest do
  # Invariant: a note's webhook that could not be delivered is a server fault, so the
  # job that runs out of attempts reaches the error page (Sentinel's error-log survey,
  # 15 Oct, item 4: a plain-text error became "Invalid", which the page leaves out).
  use ExUnit.Case, async: false

  alias AshTemplate.Actors.{Human, System}

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    address = Application.get_env(:ash_template, :notes_webhook_url)

    on_exit(fn ->
      Application.put_env(:ash_template, :notes_webhook_url, address)
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)
  end

  test "a webhook the address never answered fails as a server fault, kept on the error page" do
    wallet = "0x5555555555555555555555555555555555555555"
    account = AshTemplate.Accounts.register_verified!("did:privy:webhook-test", wallet, [wallet], actor: %System{})
    note = AshTemplate.Notes.create_note!(%{title: "Saved"}, actor: Human.for_account(account))

    # Nothing listens on the discard port.
    Application.put_env(:ash_template, :notes_webhook_url, "http://127.0.0.1:9/notes")

    assert {:error, %Ash.Error.Unknown{} = error} =
             note
             |> Ash.Changeset.for_update(:send_webhook, %{},
               context: %{ash_oban: %{job: %Oban.Job{args: %{"revision" => note.revision}}}}
             )
             |> Ash.update(authorize?: false)

    assert Exception.message(error) =~ "The note's webhook was not delivered"

    refute AshTemplate.ErrorIgnorer.ignore?(
             %ErrorTracker.Error{kind: to_string(error.__struct__)},
             %{state: :discard}
           )
  end
end

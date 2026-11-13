defmodule AshTemplate.Notes.WebhookFailureTest do
  # Invariant: a note's webhook that could not be delivered is a server fault, so the
  # job that runs out of attempts reaches the error page (Sentinel's error-log survey,
  # 15 Oct, item 4: a plain-text error became "Invalid", which the page leaves out).
  use ExUnit.Case, async: false

  alias AshOban.Errors.SnoozeJob
  alias AshTemplate.Actors.{Human, System}

  # An address that is busy and asks for a pause of the seconds its path names.
  defmodule Busy do
    @moduledoc false
    @behaviour Plug

    @impl true
    def init(options), do: options

    @impl true
    def call(%Plug.Conn{path_info: [seconds]} = conn, _options) do
      conn
      |> Plug.Conn.put_resp_header("retry-after", seconds)
      |> Plug.Conn.send_resp(429, "")
    end
  end

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

    refute AshTemplate.SavedErrors.ignore?(
             %ErrorTracker.Error{
               kind: to_string(error.__struct__),
               reason: Exception.message(error)
             },
             %{state: :discard}
           )
  end

  test "the address may pause a delivery for an hour at most; a longer pause fails the attempt" do
    wallet = "0x5555555555555555555555555555555555555555"
    account = AshTemplate.Accounts.register_verified!("did:privy:webhook-pause", wallet, [wallet], actor: %System{})
    note = AshTemplate.Notes.create_note!(%{title: "Saved"}, actor: Human.for_account(account))
    busy = start_supervised!({Bandit, plug: Busy, ip: :loopback, port: 0, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(busy)

    Application.put_env(:ash_template, :notes_webhook_url, "http://127.0.0.1:#{port}/3600")
    assert {:error, %{errors: [%SnoozeJob{snooze_for: 3600}]}} = send_webhook(note)

    Application.put_env(:ash_template, :notes_webhook_url, "http://127.0.0.1:#{port}/3601")
    assert {:error, %Ash.Error.Unknown{errors: errors}} = send_webhook(note)
    refute Enum.any?(errors, &match?(%SnoozeJob{}, &1))
  end

  # The job's run of the action, as AshOban runs it.
  defp send_webhook(note) do
    note
    |> Ash.Changeset.for_update(:send_webhook, %{},
      context: %{ash_oban: %{job: %Oban.Job{args: %{"revision" => note.revision}}}}
    )
    |> Ash.update(authorize?: false)
  end
end

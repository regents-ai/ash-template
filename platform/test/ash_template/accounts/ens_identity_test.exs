defmodule AshTemplate.Accounts.EnsIdentityTest do
  # Each sign-in asks Ethereum again for the wallet's ENS name and picture
  # (AshTemplate.Accounts.EnsIdentity). The row is written, and the person's open
  # pages told, only when what they show changes: the same answer again writes
  # and announces nothing, a new one is stored and announced, and a sign-in with
  # another wallet drops the old wallet's name at once and is looked up even
  # while an earlier lookup runs. A stand-in Ethereum endpoint answers every read
  # with nothing, so every wallet here has no name.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: AshTemplate.Repo, prefix: "ash_template_app"

  import Ecto.Query, only: [from: 2]

  alias AshTemplate.Accounts
  alias AshTemplate.Accounts.{EnsIdentity, VerifiedSession}
  alias AshTemplate.Accounts.EnsIdentity.Workers.LookUp
  alias AshTemplate.Actors.Human

  @first "0x" <> String.duplicate("e", 40)
  @second "0x" <> String.duplicate("f", 40)

  defmodule NoName do
    @moduledoc false
    # An Ethereum endpoint that answers every read with zero, so every wallet's
    # reverse record has no resolver and the wallet no name.
    @behaviour Plug

    @zero Jason.encode!(%{jsonrpc: "2.0", id: 1, result: "0x" <> String.duplicate("0", 64)})

    @impl true
    def init(options), do: options

    @impl true
    def call(conn, _options),
      do: conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, @zero)
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(AshTemplate.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    endpoint = start_supervised!({Bandit, plug: NoName, ip: :loopback, port: 0, startup_log: false})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(endpoint)
    old = Application.fetch_env(:ash_template, :ethereum_read_rpc_url)
    Application.put_env(:ash_template, :ethereum_read_rpc_url, "http://127.0.0.1:#{port}")

    on_exit(fn ->
      case old do
        {:ok, url} -> Application.put_env(:ash_template, :ethereum_read_rpc_url, url)
        :error -> Application.delete_env(:ash_template, :ethereum_read_rpc_url)
      end
    end)
  end

  test "a sign-in whose answer is unchanged writes nothing and tells no page" do
    account = sign_in(@first)
    looked_up()
    stored = identity(account)
    assert %{wallet_address: @first, ens_name: nil, lookup_state: :done} = stored
    topic = subscribe(account)

    assert sign_in(@first).id == account.id
    assert_enqueued worker: LookUp, args: %{"primary_key" => %{"id" => stored.id}}
    looked_up()

    assert identity(account) == stored
    refute_received %{topic: ^topic}
  end

  test "a changed answer is stored and every open page is told" do
    account = sign_in(@first)
    looked_up()

    # A name the wallet had until its owner took it off.
    before = Ash.Seed.update!(identity(account), %{ens_name: "gone.eth", ens_avatar_url: avatar("gone.eth")})
    assert %{ens_name: "gone.eth"} = shown(account)
    topic = subscribe(account)

    sign_in(@first)
    looked_up()

    assert %{ens_name: nil, ens_avatar_url: nil, lookup_state: :done} = now = identity(account)
    assert DateTime.after?(now.updated_at, before.updated_at)
    assert_received %{topic: ^topic}
    assert %{ens_name: nil, ens_avatar_url: nil} = shown(account)
  end

  test "a sign-in with another wallet shows no name until that wallet's own lookup answers" do
    account = sign_in(@first)
    looked_up()
    Ash.Seed.update!(identity(account), %{ens_name: "first.eth", ens_avatar_url: avatar("first.eth")})

    sign_in(@second, [@first, @second])

    assert %{wallet_address: @second, ens_name: nil, ens_avatar_url: nil, lookup_state: :pending} =
             identity(account)

    assert %{wallet_address: @second, ens_name: nil, ens_avatar_url: nil} = shown(account)
    looked_up()
    assert %{wallet_address: @second, lookup_state: :done} = identity(account)
  end

  # The lookup already running read the old wallet, so it can't finish the row.
  test "a sign-in with another wallet while a lookup runs queues the lookup for that wallet" do
    account = sign_in(@first)
    [running] = all_enqueued(worker: LookUp)

    # Oban has started it.
    started = from(j in Oban.Job, where: j.id == ^running.id)
    AshTemplate.Repo.update_all(started, [set: [state: "executing"]], prefix: "ash_template_app")

    sign_in(@second, [@first, @second])

    assert [%{id: waiting}] = all_enqueued(worker: LookUp)
    assert waiting != running.id
    looked_up()
    assert %{wallet_address: @second, lookup_state: :done} = identity(account)
  end

  # What a sign-in does: establish the account and ask for its ENS name again.
  defp sign_in(wallet, wallets \\ nil) do
    {:ok, account, []} =
      VerifiedSession.establish(%RegentPrivy.Session{
        app_id: "test-app",
        session_id: "ens-identity",
        privy_user_id: "did:privy:ens-identity",
        wallet_address: wallet,
        wallet_addresses: wallets || [wallet],
        linked_socials: [],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      })

    account
  end

  # Runs the lookup the sign-ins queued, as the `ens` queue would.
  defp looked_up,
    do: assert(%{success: 1, cancelled: 0, discard: 0, failure: 0} = Oban.drain_queue(queue: :ens))

  defp identity(%{id: id}), do: Ash.get!(EnsIdentity, %{human_account_id: id})

  # The account as its own pages read it.
  defp shown(%{id: id}) do
    {:ok, account} = Accounts.get_human_account(id, actor: %Human{human_account_id: id})
    account
  end

  # The topic the person's open pages hear the lookup on.
  defp subscribe(%{id: id}) do
    topic = EnsIdentity.topic(id)
    :ok = Phoenix.PubSub.subscribe(AshTemplate.PubSub, topic)
    topic
  end

  defp avatar(name), do: "https://metadata.ens.domains/mainnet/avatar/" <> name
end

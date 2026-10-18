# The browser walk's person: a local account on the walk's own database, signed
# in through the site's own sign-in step with a fresh session, one chat of their
# own, the longest unbroken Public Display Name the site takes (so every signed-in
# page proves a long name fits the screen), and the signed cookie the walk sends. Run by playwright.config.ts before
# the server starts; it refuses any database but the walk's local one.
alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
alias AshTemplate.Actors.Human

repo = AshTemplate.Repo.config()

unless to_string(repo[:hostname]) in ["127.0.0.1", "::1"] and
         String.ends_with?(to_string(repo[:database]), "_browser_dev"),
       do: raise("the browser walk signs in only on its own local database")

AshTemplate.LocalDatabaseFixture.ensure_human_accounts!()

wallet = "0x" <> String.duplicate("b", 40)
app_id = Keyword.fetch!(Application.fetch_env!(:ash_template, :privy), :app_id)

{:ok, account, _conflicts} =
  VerifiedSession.establish(%RegentPrivy.Session{
    app_id: app_id,
    privy_user_id: "did:privy:browser-walk",
    session_id: "browser-walk",
    wallet_address: wallet,
    wallet_addresses: [wallet],
    linked_socials: []
  })

person = Human.for_account(account)

Ash.Seed.upsert!(
  RegentIdentity.Profile,
  %{
    app_id: app_id,
    privy_user_id: "did:privy:browser-walk",
    display_name: String.duplicate("W", 80),
    wallet_addresses: [wallet],
    proof_issued_at: System.system_time(:second)
  },
  identity: :privy_subject
)

if AshTemplate.Chat.my_conversations!(actor: person) == [],
  do: AshTemplate.Chat.create_conversation!(%{title: "Browser walk"}, actor: person)

{:bootstrap, claim} = SessionAuthority.renew(nil)
{:ok, _account, bound} = SessionAuthority.sign_in(claim, account.id)

options = Plug.Session.init(Application.fetch_env!(:ash_template, :session_options))

conn =
  Plug.Test.conn(:get, "/")
  |> Map.put(:secret_key_base, AshTemplateWeb.Endpoint.config(:secret_key_base))
  |> Plug.Session.call(options)
  |> Plug.Conn.fetch_session()

conn =
  bound
  |> SessionAuthority.session()
  |> Enum.reduce(conn, fn {key, value}, conn -> Plug.Conn.put_session(conn, key, value) end)
  |> Plug.Conn.send_resp(200, "")

%{value: value} = conn.resp_cookies[options.key]

File.mkdir_p!("test/browser/.auth")

# Playwright's own saved-sign-in shape, which the walk's signed-in tests load.
File.write!(
  "test/browser/.auth/person.json",
  Jason.encode!(%{
    cookies: [
      %{
        name: options.key,
        value: value,
        domain: "127.0.0.1",
        path: "/",
        expires: -1,
        httpOnly: true,
        secure: false,
        sameSite: "Lax"
      }
    ],
    origins: []
  })
)

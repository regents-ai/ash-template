# The browser walk's person: a local account on the database made for this run,
# signed in through the site's own sign-in step with a fresh session, one chat of
# their own, one direct message to someone who wrote in General, a room that friend wrote in, the longest unbroken Public Display Name the site takes (so every
# signed-in page proves a long name fits the screen), three agents paired the way an
# agent pairs, and the signed cookie the walk sends; the friend who writes in General
# gets one too, starts a quiet room for each width's busy room (busy_room.spec.ts) and
# has a page and one more of notes (notes.spec.ts).
# Run by playwright.config.ts
# before the server starts; it refuses any database but a walk's own local one.
alias AshTemplate.Accounts.{SessionAuthority, VerifiedSession}
alias AshTemplate.Actors.Human

repo = AshTemplate.Repo.config()

unless to_string(repo[:hostname]) in ["127.0.0.1", "::1"] and
         Regex.match?(~r/\Aash_template_browser_\d+_dev\z/, to_string(repo[:database])),
       do: raise("the browser walk signs in only on its own local database")

AshTemplate.LocalDatabaseFixture.ensure_human_accounts!()

# The person signed in with their own wallet, and Privy made their Regents wallet.
wallet = "0x" <> String.duplicate("b", 40)
embedded = "0x" <> String.duplicate("9", 40)
app_id = Keyword.fetch!(Application.fetch_env!(:ash_template, :privy), :app_id)

verified = %RegentPrivy.Session{
  app_id: app_id,
  privy_user_id: "did:privy:browser-walk",
  session_id: "browser-walk",
  wallet_address: wallet,
  wallet_addresses: [wallet, embedded],
  embedded_wallet_address: embedded,
  user_wallet_address: wallet,
  linked_socials: [],
  issued_at: System.system_time(:second),
  expires_at: System.system_time(:second) + 3600
}

{:ok, account, _conflicts} = VerifiedSession.establish(verified)

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

AshTemplate.Chat.create_conversation!(%{title: "Browser walk"}, actor: person)

# Someone else, with a name of their own, writes in General, and the person
# messages them from it.
friend_wallet = "0x" <> String.duplicate("a", 40)
friend_id = "did:privy:browser-walk-friend"

Ash.Seed.upsert!(
  RegentIdentity.Profile,
  %{
    app_id: app_id,
    privy_user_id: friend_id,
    display_name: "Walk Friend",
    wallet_addresses: [friend_wallet],
    proof_issued_at: System.system_time(:second)
  },
  identity: :privy_subject
)

friend =
  AshTemplate.Accounts.register_verified!(
    friend_id,
    friend_wallet,
    [friend_wallet],
    actor: %AshTemplate.Actors.System{}
  )

as_friend = [actor: Human.for_account(friend), context: %{client_key: "browser-walk-friend"}]
said = AshTemplate.Rooms.post_message!(%{room: "general", body: "Hello from the walk."}, as_friend)

# A room the friend started and wrote in, which the walk only reads, for each width to
# report their message (reports.spec.ts): with nobody else writing there, the message
# stays where its menu points.
reports = AshTemplate.Rooms.create_room!(%{name: "Walk Reports", topic: "Reports from the walk"}, as_friend)
AshTemplate.Rooms.post_message!(%{room: reports.slug, body: "Report this one."}, as_friend)

# A room for each width's busy room (busy_room.spec.ts), where only the person and
# the friend write, so nothing else moves the list while the walk measures it.
for width <- ["Desktop", "Phone"] do
  AshTemplate.Rooms.create_room!(%{name: "Walk Busy #{width}", topic: "A busy room on the walk"}, as_friend)
end

# A room for each width where the friend likes the person's message and comes and
# goes (likes.spec.ts), so who is here there is only those two. The friend has
# started as many rooms as a day allows above, and the person starts one on each
# width in the walk, so these are put in place as they would be saved.
for width <- ["desktop", "phone"] do
  Ash.Seed.seed!(AshTemplate.Rooms.Room, %{
    slug: "walk-likes-#{width}",
    name: "Walk Likes #{String.capitalize(width)}",
    topic: "Likes on the walk",
    created_by_id: friend.id
  })
end

conversation = AshTemplate.Dms.open_conversation!(said.id, actor: person)
AshTemplate.Dms.send_dm!(conversation.id, %{body: "Hello back."}, actor: person)

# Fifty-one notes the friend wrote, one more than a page, for Older notes to show
# the last (notes.spec.ts).
for n <- 1..51 do
  Ash.Seed.seed!(AshTemplate.Notes.Note, %{title: "Walk note #{n}", human_account_id: friend.id})
end

# A poll the friend started, open for the whole walk, for the poll page to show.
AshTemplate.Polls.start_poll!(%{question: "Tea or coffee?", choices: ["Tea", "Coffee"], minutes: 60},
  actor: Human.for_account(friend)
)

# A poll the person started for each width, open for the whole walk, for Vote and End
# to wait while the connection is down (blocked_websocket.spec.ts). Started here, it
# leaves the person's daily polls to polls.spec.ts.
for width <- ["desktop", "phone"] do
  AshTemplate.Polls.start_poll!(
    %{question: "Walk offline, #{width}?", choices: ["Yes", "No"], minutes: 60},
    actor: person
  )
end

# A fourth agent, paired first, which the account menu's three leave out
# (account_menu.spec.ts); the agent the walk opens on the Agents page, and one for
# each width to rename (agents.spec.ts).
for {name, digit} <- [
      {"Spare Agent", "f"},
      {"Walk Agent", "c"},
      {"Desktop Agent", "d"},
      {"Phone Agent", "e"}
    ] do
  code =
    RegentAgents.issue_pairing_code!(actor: %RegentAgents.Person{privy_user_id: account.privy_user_id})

  RegentAgents.pair_agent!(code.code, name, :hermes,
    actor: %RegentAgents.Agent{wallet: "0x" <> String.duplicate(digit, 40)}
  )
end

options = Plug.Session.init(Application.fetch_env!(:ash_template, :session_options))

File.mkdir_p!("test/browser/.auth")

# The walk's own address, where its browser keeps the homepage's guided tour seen, as
# playwright.config.ts does for a walk that is not signed in.
walk_origin = "http://127.0.0.1:" <> System.fetch_env!("PORT")

# Signs `account` in through the site's own sign-in step with a fresh session and
# writes the cookie in Playwright's own saved-sign-in shape, which a test loads.
save_sign_in = fn account, verified, file ->
  {:bootstrap, claim} = SessionAuthority.renew(nil)
  {:ok, _account, bound} = SessionAuthority.sign_in(claim, account.id)

  conn =
    Plug.Test.conn(:get, "/")
    |> Map.put(:secret_key_base, AshTemplateWeb.Endpoint.config(:secret_key_base))
    |> Plug.Session.call(options)
    |> Plug.Conn.fetch_session()

  conn =
    bound
    |> SessionAuthority.session()
    |> Map.put("wallets", VerifiedSession.wallet_labels(verified))
    |> Enum.reduce(conn, fn {key, value}, conn -> Plug.Conn.put_session(conn, key, value) end)
    |> Plug.Conn.send_resp(200, "")

  %{value: value} = conn.resp_cookies[options.key]

  File.write!(
    "test/browser/.auth/#{file}",
    Jason.encode!(%{
      cookies: [
        %{
          name: options.key,
          value: value,
          domain: "127.0.0.1",
          path: "/",
          expires: -1,
          httpOnly: true,
          secure: true,
          sameSite: "Lax"
        }
      ],
      origins: [
        %{
          origin: walk_origin,
          localStorage: [%{name: "ash-template:tour:home", value: "seen"}]
        }
      ]
    })
  )
end

save_sign_in.(account, verified, "person.json")

save_sign_in.(
  friend,
  %RegentPrivy.Session{
    app_id: app_id,
    privy_user_id: friend_id,
    session_id: "browser-walk-friend",
    wallet_address: friend_wallet,
    wallet_addresses: [friend_wallet],
    user_wallet_address: friend_wallet,
    linked_socials: []
  },
  "friend.json"
)

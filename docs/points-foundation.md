# Points foundation — shared package, earning disabled

The reference implementation uses `regent_points` from elixir-utils/points.
The package owns the ledger, rules, NFT reads, jobs and migrations. The template
supplies configuration, verified account callbacks and the Account Points page.

## Approved basis and caps

Every repeat (daily) action shares one allowance of 100 points per UTC day, whoever
acted: the person or any of their paired agents. Each action's own count (for
example, once a day) is also shared by the person and their agents. The most an
account earns in a day before the bonus is therefore 100 points. One-time actions
sit outside every daily cap.

Authenticated connected-agent actions follow the same rules through supported
WebMCP, HTTP, CLI and MCP routes. More wallets, keys or agents never create more
allowances. The rates and caps live in `RegentPoints.Rules` (elixir-utils/points);
this section describes that code.

## Repeat actions

Earning remains disabled. The catalog's repeat actions, each counted against the
shared 100-point daily allowance:

| Completed action | Points | Times per day |
| --- | ---: | ---: |
| Autolaunch auction created | 20 | 1 |
| Autolaunch auction bid | 20 | 1 |
| Autolaunch token trade | 10 | 1 |
| Keyfleet key bought | 10 | 5 |
| Patchbay Offer placed | 5 | 10 |
| Patchbay report published | 10 | 1 |
| Patchbay reply published | 5 | 1 |

There is no active-day or recurring voting award. Keyfleet rollcall and
independently verified Patchbay repair stay out of the catalog until their
products exist (Sean, 8 October).

Server and confirmed on-chain versions of the same action share one business
identity and allowance. The source adapter must establish that the action
exists in the current product, verify the key's authorization and freeze its human
beneficiary at the action's ownership epoch. A wallet press, approval, reverted
transaction, UI success flag, issued handoff credential or merely opening a tool earns
nothing. Keyfleet receives no work-management or productivity-scoring system.

Patchbay evidence must identify the canonical asker and replier. The source
adapters must reject duplicate and spam awards and support review of reciprocal
patterns. Different accounts alone do not prove independence. These adapters and
pattern review remain launch requirements. Existing correction entries can
invalidate awards without reopening limits.

Capped awards show the points before limits and the points awarded. For example, a
20-point action with 8 points of allowance remaining earns 8, with 12 excluded by
the cap; the entry reads "Allowance reached".

## One-time milestones

Each milestone earns once per account, across every site, wallet, key and agent.
Once one has earned, a later qualifying action records nothing more, and two
qualifying actions at the same moment still earn it once. The catalog totals
**250 points**, and **240** can be earned at launch: the first agent note stays in
the catalog but is not approved at launch (Sean, POINTS-CATALOG b, 6 November):

| Group | Milestones | Total |
| --- | --- | ---: |
| Account | Activated 25; X, GitHub and Farcaster linked 10 each | 55 |
| Agents | First paired agent 25; first note written by your agent 10 (`template.first_agent_note`, not at launch) | 35 |
| Autolaunch | First graduation 50; first auction settled 10; token staked 40 | 100 |
| Keyfleet | First membership 10; key revealed 5; agent authorized 10; message 5; vote 10; Twigpine and ActiveGraph used 10 each | 60 |

Availability of a catalog row does not assert that its verifier or source hook
exists. Milestones do not reset by program, season, site, wallet, agent, rule
version or ordinary disconnection. Provider and registration subject claims
additionally prevent moving the same proof between accounts to earn again.

A rule keeps its id when it changes: each catalog entry carries its version, a new
id is only for a new action, and the ledger keeps the version each entry was earned
under. To stop a rule, take it off `approved_rules`.

What an account already had at the start earns at the start time, at most 80
points, without the person doing anything (Sean, POINTS-EXISTING a, 6 November):
the account, its linked X, GitHub and Farcaster accounts still linked, and its
first paired agent still paired. `RegentPoints.StartAwards` runs hourly on every
site, asks each checker's `existing/2` and records through the normal path, so an
account earns each once whichever site records it. No other rule earns for what
happened before the start.

## NFT bonus

Combine the verified linked wallets' holdings across these Base collections:

- Animata I: `0x78402119ec6349a0d41f12b54938de7bf783c923`
- Animata II: `0x903c4c1e8b8532fbd3575482d942d493eb9266e2`
- Regents Club: `0x2208aadbdecd47d3b4430b5b75a175f6d885d487`

1–2 NFTs add 20%; 3–6 add 45%; 7 or more add 75%. Awards save points only; the
bonus is added once per program period, when the period ends (Sean, 9 October).
Periods last 30 days, counted from the program start, and there are three: the
seasons (Sean, 13 November). Nothing done after the third's end earns; its bonus is
still added after it, and no later period is tallied. The tier the account's wallets
hold on the tally day applies once, without stacking, to the points earned in that
period after limits, one-time awards included. Regents runs the tally; each account
and period gets one saved bonus row. While a season runs, the Points page shows
the tier the wallets hold now, read from Base when the page opens and never saved.
Outside the seasons it reads no NFTs, and the shared Bonus card is in its state for
before the first season (`:closed`) or after the last (`:ended`), from
`RegentPoints.Seasons.phase/1`. Account merging remains deferred.

## Source integration

`RegentPoints.record_event/2` accepts a server-only source reference: `rule_id`,
`source_app`, `source_kind`, `source_event_key`. Call it inside the source transaction.
Only an Oban job is inserted there, so the action and its Points job commit or roll
back together; an insert failure rolls back the action.

The configured adapter verifies committed facts in the background. Invalid evidence
and conflicting source identities receive a private, durable rejection audit.
Events save the rule's points and daily caps; delayed awards use that snapshot.
The template configures four adapters:

- A new account (`AshTemplate.Points.AccountActivated`, rule `account.activated`, source
  `regents`/`account`, recorded by `HumanAccount` `:register_verified` only when the
  sign-in inserted the account).
- A linked social account (`AshTemplate.Points.LinkedSocial`, rules `social.x`,
  `social.github` and `social.farcaster`, source `template`/`linked_identity` keyed
  `provider:subject`, recorded by `LinkedIdentity` `:upsert_verified` only for a subject new
  to the account; a sign-in with the same subject refreshes it through
  `:refresh_verified`). It earns at the link's `inserted_at`, when that subject was linked.
- A paired agent (`AshTemplate.Points.PairedAgent`, rule `agent.activated`, source
  `template`/`pairing`, recorded by the pairing through `RegentAgents.Signals`).
- A note an agent writes for its person (`AshTemplate.Points.AgentNote`, rule
  `template.first_agent_note`, source `template`/`note`, recorded by the note's create
  action).

Both agent awards read the pairing through `RegentAgents.pairing_history/1`, which keeps
unpaired agents, and name the agent's wallet as the actor; the pairing id stays in the
evidence. `AshTemplate.Points.Accounts.agent_names/2` names each wallet from the person's
newest pairing of it (`RegentAgents.pairing_histories/1`). The site never queries
`regent_agents` itself.

See the package README for the adapter contract, actor policy and migration instructions.

## Account Points page

`/account/points` is drawn with `Regent.Points` from the design system, on figures
`AshTemplateWeb.PointsEntries` formats. It shows, in order on a phone:

- **Total**, large, on the site's band colour, with what the account earned today
  and yesterday (UTC days), its rank, and one sentence saying Points are a record
  of activity. It says nothing about value.
- **To do**: `RegentPoints.Rules.tracked/0`, only the catalog rules this site has an
  adapter for and that are approved, so it never offers an action nothing records.
  One-time actions and daily ones are listed apart, each with its points; the ones
  left come first with a link to where each is done, the ones done are ticked. A daily
  action shows how much of today's count is used. Under the title, one line says where
  Points stands: not started, its start date, the season running and its days left,
  or the last season over. After the last season nothing earns and no action is
  listed. Before the start, each start rule
  (`RegentPoints.Rules.start_rules/0`) the account already meets is ticked and marked
  as added at the start. Each start adapter's `held/2` answers that for the one
  account, from the same tables its `existing/2` reads for the start itself.
- **Leaderboard**: the ten highest totals by the name and picture the site already
  shows the public, the reader's row marked. A reader below the ten gets their own
  place on a row under the list. Accounts level on points share a place: one more
  than the number of totals strictly above. Inside a tie the lower account id comes
  first, the same on every read. `AshTemplate.Points.Accounts.people/1` supplies the
  names.

  The board is one shared reading, the same for every signed-in reader
  (`AshTemplate.Points.Board`, kind `points_board` in `AshTemplate.SharedReading`).
  It reads `RegentPoints.leaderboard/1` under the system actor at most once a second
  after any award, correction or period bonus on this site (`points:board`), and
  each minute from the heal line, which also catches awards made on the other
  sites. Each account stores its total (`balance_micro` in the shared Points
  schema), moved by every award, correction and period bonus in the same
  transaction, and the board reads the ten highest from an index on it: the same
  ten rows however many accounts have points. It holds those rows with their
  account ids, highest first. A reader's place comes with their summary
  (`place` in `RegentPoints.summary/1`): one count of the accounts above them on
  the same index, read when the page opens and when their own Points change. The
  ids stay on the server: a page or an agent gets the rows without ids, a mark on
  its own row and its own place. While the board has never been read the page
  shows it as loading or not read, and the agent's whole Points answer is
  "unavailable".

  Size: the kind accepts 65,536 bytes. With a 1 KB name, a 2.3 KB square pattern, a
  1 KB picture address and an ENS name on every row, ten rows measure about 48 KB,
  whatever the number of accounts. Each board read reports its size as a percent
  of the limit (`health.shared_reading.size.percent`, kind `points_board`). A
  larger board is refused and marked degraded; the last one stays shown as behind,
  and the agent's answer keeps giving it.
- **Bonus**: the three NFT tiers with the one held marked, then each season: its dates
  (none until a start is set), what the account earned in it once it began, and the
  bonus added at its end. Seasons are the library's: three 30-day periods from the
  start, season n being period n (`RegentPoints.Seasons`, the number in
  `RegentPoints.Rules.season_count/0`). After the last season's end nothing earns,
  and the last season's bonus is still added after it. The tip under Bonus says what
  a season is.
- **Activity**: each entry with who earned it (you or the agent's name), when, and
  whether it was cut by a daily limit or is a correction.

The agent tool `account_points` answers with the same figures: `points`,
`earned_today`, `earned_yesterday`, `rank`, `to_do`, `daily_limits`, `leaderboard`,
`entries` and `seasons`, each `to_do` item marking `at_start`. Both read
`AshTemplate.Points.my_points/1`: the library's summary, each season with what was
earned in it and its bonus, and before the start the start rules the account already
meets. A site that adds an adapter shows its rule without changing the page; a start
rule's adapter also needs `held/2`.

## Local development and launch

The template has one Git dependency for Points, pinned with the same
`@elixir_utils_ref` as the other shared packages.

The shared migrations live only in elixir-utils/points/priv/repo/migrations.
`RegentPoints.Migrator.up/1` uses a dedicated connection and shared migration history.
Regents runs the production migrations and the NFT bonus tally at each period end; other
sites, the template included, only read and award. Schema changes require Sean's grant.
The package ships one generated initial migration. Under Sean’s POINTS-8 approval,
the old local Points fixture schema was backed up and rebuilt successfully.
Canonical users, Credits, legacy queued jobs and other schemas were left intact.

The five start rules are approved in `platform/config/config.exs`, which sets no start,
so nothing earns in development or tests. The hosted template's start is in
`platform/config/prod.exs`: 16 November 2026 17:00 UTC. The NFT reads use the latest Base block through the site's chain client
(`chain_nodes[8453]`).
Full Account filters/detail navigation remain separate work.

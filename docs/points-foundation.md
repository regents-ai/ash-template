# Points foundation — shared package, earning disabled

The reference implementation uses `regent_points` from elixir-utils/points.
The package owns the ledger, rules, NFT reads, jobs and migrations. The template
supplies configuration, verified account callbacks and the Account Points page. Points and Credits remain separate.

## Approved basis and caps

1 point per USDC spent on purchased Credits, capped at 50 points per UTC day.
Promotional Credits, gifts and later spending do not earn this purchase award.
Every repeat (daily) action shares one allowance of 100 points per UTC day, whoever
acted: the person or any of their paired agents. Each action's own count (for
example, once a day) is also shared by the person and their agents. The most an
account earns in a day before the bonus is therefore 150 points. One-time actions
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
**335 points**:

| Group | Milestones | Total |
| --- | --- | ---: |
| Account | Activated 25; X, GitHub and Farcaster linked 10 each; verified ENS name chosen 25 | 80 |
| Agents | First paired agent 25; first note written by your agent 10 (`template.first_agent_note`) | 35 |
| Patchbay | First report 10; first reply 10 | 20 |
| Autolaunch | First launch 20; first graduation 50; first auction settled 10; token staked 40 | 120 |
| Keyfleet | First membership 10; key revealed 5; agent authorized 10; message 5; vote 10; marimo, dDocs, Twigpine and ActiveGraph used 10 each | 80 |

Availability of a catalog row does not assert that its verifier or source hook
exists. Milestones do not reset by program, season, site, wallet, agent, rule
version or ordinary disconnection. Provider and registration subject claims
additionally prevent moving the same proof between accounts to earn again.
Already-completed verified setup qualifies once at its actual verification time
after launch, without reconnecting. This does not authorize historical activity
backfill.

## NFT bonus

Combine the verified linked wallets' holdings across these Base collections:

- Animata I: `0x78402119ec6349a0d41f12b54938de7bf783c923`
- Animata II: `0x903c4c1e8b8532fbd3575482d942d493eb9266e2`
- Regents Club: `0x2208aadbdecd47d3b4430b5b75a175f6d885d487`

1–2 NFTs add 20%; 3–6 add 45%; 7 or more add 75%. Awards save points only; the
bonus is added once per program period, when the period ends (Sean, 9 October).
Periods last 30 days, counted from the program start. The tier the account's wallets
hold on the tally day applies once, without stacking, to the points earned in that
period after limits, one-time awards included. Regents runs the tally; each account
and period gets one saved bonus row. While earning is open, the Points page shows
the tier the wallets hold now as "Bonus this period", read from Base when the page
opens and never saved; while earning is off it reads no NFTs and says they are
counted once earning opens. Account merging remains deferred.

## Source integration

`RegentPoints.record_event/2` accepts a server-only source reference: `rule_id`,
`source_app`, `source_kind`, `source_event_key`. Call it inside the source transaction.
Only an Oban job is inserted there, so the action and its Points job commit or roll
back together; an insert failure rolls back the action.

The configured adapter verifies committed facts in the background. Invalid evidence
and conflicting source identities receive a private, durable rejection audit.
Events save the rule's Credits rate and daily caps; delayed awards use that snapshot.
The template configures two adapters: Credits purchases
(`AshTemplate.Points.CreditsPurchase`) and a note an agent writes for its person
(`AshTemplate.Points.AgentNote`, rule `template.first_agent_note`, source
`template`/`note`, recorded by the note's create action). See the package README for the adapter
contract, actor policy and migration instructions.

## Account Points page

`/account/points` lists `RegentPoints.Rules.tracked/0`: only the catalog rules this
site has an adapter for, so it never offers an action nothing records. Today that is
Credits bought and "First note written by your agent", plus the NFT bonus tiers. The
daily allowances shown are those of the rules earning now (`RegentPoints.Summary`),
so none show while earning is off. Each entry says who earned it (you or the agent's
name) and whether it counted in full, reached an allowance, or is a correction. The
agent tool `account_points` answers with the same entries and allowances. A site that adds an
adapter shows its rule without changing the page.

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

Earning remains disabled: no start time or approved rules are configured. Before
launch, implement trusted sources and complete live acceptance. The NFT reads use the latest Base block through the site's chain client
(`chain_nodes[8453]`).
Full Account filters/detail navigation remain separate work.

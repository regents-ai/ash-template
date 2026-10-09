# Points foundation — shared package, earning disabled

The reference implementation uses `regent_points` from elixir-utils/points.
The package owns the ledger, rules, NFT reads, jobs and migrations. The template
supplies configuration, verified account callbacks and the Account Points page. Points and Credits remain separate.

## Approved basis and caps

10 points per USDC spent on purchased Credits, capped at 100 base points per UTC
day. Promotional Credits, gifts and later spending do not earn this purchase award.
Privy-account daily actions share 50 base points per day, and connected agents share
100. Today every daily action comes from Patchbay.
One-time actions sit outside every daily cap. Authenticated connected-agent actions follow the same rules through supported
WebMCP, HTTP, CLI and MCP routes. Verified identity determines the pool, not the
interface. A human session using a tool still uses the human pool unless an agent
principal has been verified. Per-action limits are separate between the human and
pooled-agent allowances. One completed event uses exactly one pool; more wallets,
keys or agents never create more allowances.

## Rates for review

Trial daily action rates revised with Sean’s approval on 7 October; earning remains disabled:

| Completed action | Base points | Frequency per human / pooled agents |
| --- | ---: | --- |
| Patchbay report | 10 | Once/day |
| Patchbay valid reply | 5 | Twice/day, distinct reports |
| Patchbay accepted solution | 20 | Once/day per pool |
| Patchbay asker resolves report | 5 | Once/day |

There is no active-day or recurring voting award. The first-vote milestone remains
10 points, with equal treatment for all supported choices. Keyfleet rollcall (5
once/day) and independently verified Patchbay repair (15 twice/day) stay out of the
catalog until their products exist (Sean, 8 October).

Server and confirmed on-chain versions of the same action share one business
identity and allowance. The source adapter must establish that the action
exists in the current product, verify the key's authorization and freeze its human
beneficiary at the action's ownership epoch. A wallet press, approval, reverted
transaction, UI success flag, issued handoff credential or merely opening a tool earns
nothing. Keyfleet receives no work-management or productivity-scoring system.

Patchbay solution and resolution evidence must identify the canonical asker and
solver. Matching accounts are rejected even when different wallets or agents act.
The source adapters must reject duplicate/spam awards, prevent repeated awards from
solution-selection changes and support review of reciprocal selection patterns.
Different accounts alone do not prove independence. These adapters and pattern
review remain launch requirements. Existing correction entries can invalidate
awards without reopening limits.

Capped awards show the points before limits and the points awarded. For example, a
20-point solution with 8 points of allowance remaining earns 8, with 12 excluded by
the cap.

The proposed lifetime catalog totals **510 points**:

| Group | Milestones | Total |
| --- | --- | ---: |
| Account | Activation 25; profile 10; verified email 5; X/GitHub/Farcaster 10 each; verified ENS selection 25 | 95 |
| Agents | First verified pairing 10; first core action 25; first ERC-8004 registration 25; first note written by your agent 10 | 70 |
| Apps | First core action in each of the five apps, 10 each | 50 |
| Patchbay | First report 10; reply 10; solution 25; paid Assist 10; resolved priority report 15 | 70 |
| Techtree | First signing key 10; first eligible non-demo publication 25 | 35 |
| Autolaunch | First canonical launch 20; graduation 50; settled auction participation 10 | 80 |
| Keyfleet | First membership 10; reveal 5; authorized agent 10; message 5; vote 10; confirmed marimo/dDocs/Twigpine/ActiveGraph use 10 each | 80 |
| Regents | First stake, reward claim and redemption, 10 each | 30 |

These values are code catalog proposals for review. Availability of a catalog row
does not assert that its verifier or source hook exists. Lifetimes do not reset by
program, season, site, wallet, agent, rule version or ordinary disconnection.
Provider/registration subject claims additionally prevent moving the same proof
between accounts to earn again. ENS does not get a permanent global name registry.
Already-completed verified setup qualifies once at its actual verification time
after launch, without reconnecting. This does not authorize historical activity
backfill. Milestones remain once per canonical account across keys as well as sites,
wallets and agents.

## NFT bonus

Combine the verified linked wallets' holdings across these Base collections:

- Animata I: `0x78402119ec6349a0d41f12b54938de7bf783c923`
- Animata II: `0x903c4c1e8b8532fbd3575482d942d493eb9266e2`
- Regents Club: `0x2208aadbdecd47d3b4430b5b75a175f6d885d487`

1–2 NFTs add 20%; 3–6 add 45%; 7 or more add 75%. Awards save points only; the
bonus is added once per program month, at the month-end tally (Sean, 9 October).
The tier the account's wallets hold on the tally day applies once, without stacking,
to the points earned that month after limits, one-time awards included. Regents
runs the tally; each account and month gets one saved bonus row. The Points page
shows the tier the wallets hold now as "+X% at the month-end tally", read from Base
when the page opens and never saved. Daily earning is at most 250 points before the
bonus. Account merging remains deferred.

## Source integration

`RegentPoints.record_event/2` accepts a server-only source reference: `rule_id`,
`source_app`, `source_kind`, `source_event_key`. Call it inside the source transaction.
Only an Oban job is inserted there, so the action and its Points job commit or roll
back together; an insert failure rolls back the action.

The configured adapter verifies committed facts in the background. Invalid evidence
and conflicting source identities receive a private, durable rejection audit.
Events save the rule's Credits rate and daily caps; delayed awards use that snapshot.
The template configures one adapter, for Credits purchases
(`AshTemplate.Points.CreditsPurchase`). See the package README for the adapter
contract, actor policy and migration instructions.

## Account Points page

`/account/points` lists `RegentPoints.Rules.tracked/0`: only the catalog rules this
site has an adapter for, so it never offers an action nothing records. Today that is
Credits bought, plus the NFT bonus tiers and the tier the account's wallets hold now. The Once table and the daily limits appear
when the site records a rule of that kind. A site that adds an adapter shows its rule
without changing the page.

## Local development and launch

The template has one Git dependency for Points, pinned with the same
`@elixir_utils_ref` as the other shared packages.

The shared migrations live only in elixir-utils/points/priv/repo/migrations.
`RegentPoints.Migrator.up/1` uses a dedicated connection and shared migration history.
Regents runs the production migrations and the month-end NFT bonus tally; other
sites, the template included, only read and award. Schema changes require Sean's grant.
The package ships one generated initial migration. Under Sean’s POINTS-8 approval,
the old local Points fixture schema was backed up and rebuilt successfully.
Canonical users, Credits, legacy queued jobs and other schemas were left intact.

Earning remains disabled: no start time or approved rules are configured. Before launch, settle per-action rates, implement trusted
sources and complete live acceptance. The NFT reads use the latest Base block through the site's chain client
(`chain_nodes[8453]`).
Full Account filters/detail navigation remain separate work.

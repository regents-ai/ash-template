# How each site watches the chain today

Checked 2026-09-26; Keyfleet's, Autolaunch's and Patchbay's rows 2026-11-16. Read every
site with `git show origin/main:<path>`; local checkouts lag behind.

| Site | Watcher | Row identity | Pages hear through |
| --- | --- | --- | --- |
| Keyfleet (`origin/main` cc0d248d) | `Keyfleet.Chain.ReadFleet` (one Oban job per fleet) and `Scanner`, at `latest`, cursor per fleet. Sent wallet steps are read by `KeyfleetWeb.OnchainSteps` through `Keyfleet.Chain.Client` at `latest` every 2 s; nothing stored | `[:transaction_hash, :log_index]` | Plain `Phoenix.PubSub` topics (`Keyfleet.Proposals.topic/1`, `Keyfleet.Keys.topic/1`) |
| Autolaunch (`origin/main` e899c4e5) | One Oban job for each thing read, each kept by `Autolaunch.ChainWatch`, all at `latest`: `CoveredCalls.Sales` (covered-call sales), `AuctionActivity` (bids, prices, settlements), `TokenTrades` (trades, stakes, revenue), `AuctionMarket` (each auction's state) | Sales and stakes `[:chain_id, :transaction_hash, :log_index]`; trades `[:token_id, :transaction_hash, :log_index]`; bids `[:auction_id, :bid_id]`; prices and settlements `[:auction_id, :block_number, :log_index]` | Ash `pub_sub` on the listing resources, re-read at most once a second (`AutolaunchWeb.LiveListings`) |
| Patchbay (`origin/main` 5309791d) | `Patchbay.Offers.ReadMarket` (one Oban job for the market) and `Patchbay.Offers.Scanner`, at `latest` | `[:chain_id, :transaction_hash, :log_index]` on placements, terminations, leases and settlements | Ash `pub_sub` on those four resources, topic `Patchbay.Offers.topic/0` |
| Regents | None; staking reads the chain directly (`AshPlatform.Staking.RpcClient`) | | |
| Techtree | None | | |

## Models

- Keeping the first saved row (rule 6): Autolaunch's covered-call reader,
  `platform/lib/autolaunch/covered_calls/sales.ex` (`compare/4`, the warning once a
  transaction's block is read for the last time), its resources `covered_calls/sale.ex`
  (the `:seen` read) and `covered_calls/cursor.ex`, and its tests in
  `platform/test/autolaunch/points_covered_call_awards_test.exs`; and Patchbay's offer
  reader, `platform/lib/patchbay/offers/scanner.ex` and `cursor.ex`, with
  `platform/test/patchbay/offers/scanner_test.exs`.
- The reading job, its watch and the stub client: Keyfleet,
  `platform/lib/keyfleet/chain/` (`read_fleet.ex`, `watch.ex`) and
  `test/support/chain_stub_client.ex`.
- The page: Autolaunch, `platform/lib/autolaunch/auction.ex` (`pub_sub`),
  `platform/lib/autolaunch/auction_activity.ex` (notices sent once its own transaction
  commits) and `platform/lib/autolaunch_web/live/live_listings.ex` (subscribe when
  connected, one re-read a second).

## Where sites differ from this skill

Each is a backlog item for that site.

1. **Keyfleet halts a fleet's reading at a disagreement.** A row read again that differs,
   or a recorded block whose hash changed, flags the fleet's cursor
   (`Keyfleet.Chain.Scanner`, `scanner.ex:125`, `:333`, `:432-444`; `flag_divergence`
   in `cursor.ex:96-111`), and nothing of that fleet is read again until an operator runs
   `bin/clear-fleet-stop` on the live machine. Rule 6 keeps the first saved row, warns
   once and reads on.
2. **Keyfleet's rows carry no `chain_id`** in their identity, and its pages hear through
   plain PubSub topics rather than the resource's notifier.
3. **Autolaunch's bid, price, settlement, trade and revenue rows are removed and saved
   again.** `AuctionActivity` deletes and writes again the bids, prices and settlements
   of each range it reads again; `TokenTrades` deletes the trades it no longer reads
   there and replaces the revenue; and both drop an auction's or token's rows and
   rebuild them when the cursor's block hash changed (`auction_activity.ex:579-590`,
   `:677-683`; `token_trades.ex:663-667`, `:704-708`), with `Repo.delete_all` past
   Ash's actions. Rule 6 keeps every saved row; its covered-call sales and stakes
   already do.
4. **Autolaunch's covered-call reader passes over a log it cannot decode**, with one
   warning when its block is first read (`sales.ex`, `decode/4`). Rule 6 reads it again
   until the code is fixed, as Patchbay's reader does.
5. **Autolaunch reads two figures at `safe`**: `regent_facts.ex:138` and
   `treasury_chain_client.ex:95` (whose receipts must stand at or below that block,
   `:276`). Rule 1 says `latest`.
6. **Patchbay names a transaction that no longer matches in every pass** while its block
   is among the 300 read again (`scanner.ex:138-153`), where rule 6 gives one warning.
   It also saves a log of a saved transaction read from the block it was saved from
   (`:207-229`), and ends the pass to be tried again when a saved log is missing from a
   block whose hash is unchanged (`:191-205`).
7. **Patchbay's offers page reads the board again on every notice**
   (`PatchbayWeb.OffersLive`, `handle_info(:offers_changed, …)`), where rule 9 joins the
   notices of one second into one read.

## Base block counts to change for Denim (rule 13)

Checked 2026-10-30 against each repository's main. The full list and owners are in
`control/coordination/BASE-DENIM-2026-11-05.md`; each owner records progress there.

| Where | Today | On Base from 5 Nov 2026 | Owner |
| --- | --- | --- | --- |
| Keyfleet scanner | 30-block re-read, 300-block freshness | 300 and 3,000 | Keyfleet chief |
| Sentinel chain watch | 1,350-block window | 13,500, in bounded stretches | Sentinel chief |
| Autolaunch | Two-second block estimates, launch discovery offsets, Base ledger pass and walk-back of 8, 1,000-block admissions re-read, REGENT page logs over 302,400 blocks (seven days) | Counts from time per rule 13, offsets by contract version; bids and trades in chain order | Autolaunch chiefs |
| regents.sh staking revenue history | 302,400 blocks for seven days | 3,024,000 | Regents chief |

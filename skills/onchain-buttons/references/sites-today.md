# How each site does it today

Checked 2026-09-26. Read before changing a site's wallet code, and read the right checkout:
the local Autolaunch, Techtree and Patchbay checkouts lag behind, so read those with
`git show origin/main:<path>`. Regents and KeyFleet local `main` were current.

| Site | Steps built by | Result checked by | Sends from |
| --- | --- | --- | --- |
| Autolaunch (`origin/main` 1b0e56c) | The server, pushed as a review | The server at `latest`, every 2 s | The signed-in wallet |
| Regents (`main` 10c6b13) | Redeem: the server (`redemption/actions.ex`, `wallet_actions/envelope.ex`), re-encoded in the browser as a check. Staking: the browser (`wallet_actions/staking.ts`) | The server, after the hook reports the hash (`observe_staking_transaction`) | Privy's selected wallet (`activeEthereumWallet()`) |
| KeyFleet (`main` 59d4d5f) | The browser, from the rendered order (`readKeyOrder` in `wallet_actions/buy_key.ts`) | The browser, which waits for each receipt (`confirmed` in `wallet_actions/chain_call.ts`) | Privy's selected wallet (`activeEthereumWallet()`) |
| Patchbay | Signs x402 typed data only (`signTypedData` in `platform/assets/js/privy_bridge.jsx`) | The server, with the signature | The signed-in wallet as Privy holds it connected |
| Techtree (`origin/main` c6c07a1) | No on-chain buttons | | |

## The closest to this skill

Autolaunch's staking panel:

- `platform/assets/js/hooks/autolaunch_reviewed_steps.ts`: the hook, presses and reports.
- `platform/assets/js/wallet_actions/autolaunch_network.ts`: `sendLabTransaction`, with
  the chain switch, the fork check and the wallet-swap checks.
- `platform/lib/autolaunch_web/live/stake_component.ex`: `next_step`, the 2 s check,
  "Check again", and `wallet_failure_copy`.
- `platform/lib/autolaunch/stocks/stake_actions.ex` (`verify/4`) and
  `platform/lib/autolaunch/chain/rpc.ex` (`canonical_outcome_evidence/6`).

## Where sites differ from this skill

Each is a backlog item for that site, not something to copy.

1. **Regents and KeyFleet send from Privy's selected wallet**, not the signed-in one
   (their stake, redeem and buy hooks call `activeEthereumWallet()`). Rule 3 says the
   signed-in wallet.
2. **Regents redeem asks the server for the step after the press** (`prepare_redemption`),
   so the wallet waits on a round trip, and changing the selection clears the presses
   still waiting (`clearPendingInitiators`): their reviews then arrive to no press and are
   dropped. Both hooks also keep a queue of presses. Rule 1 says every press reaches the
   wallet.
3. **Autolaunch's bid, launch and subject-wallet hooks** use the older
   `hooks/wallet_presses.ts`, which records presses on the server; a press made before its
   review arrives is dropped.
4. **Regents staking and KeyFleet build their steps in the browser**
   (`wallet_actions/staking.ts`, `buy_key.ts`, `fleet_action.ts`). Rule 4 has the server
   build them and push a review, as Autolaunch does; Regents already has unused
   `AshPlatform.Staking.prepare_*` actions for it. Regents redeem is built on the server
   but re-encoded in the browser as a check, which goes too.
5. **KeyFleet confirms in the browser** and sends the purchase from the same press once
   the approval's receipt arrives. Rule 8 has the server check the result, which makes the
   approval a step with its own button.
6. **Not audited yet:** whether any site has an on-chain button with `phx-click`, or one
   inside a `phx-submit` form. Both silently swallow repeat presses (rule 2).

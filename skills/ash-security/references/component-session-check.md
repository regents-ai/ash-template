# LiveComponents re-check the session on their own events

A page's `attach_hook(:session_authority_event, :handle_event, ...)` never runs for an
event targeted at a LiveComponent (`phx-target={@myself}`, `pushEventTo`). A component
that acts with an actor built from its assigns keeps acting for the person the page
was given at mount, even after that session is signed out elsewhere. Every component
that handles events and acts for a person carries its own check, and acts on the
account as it reads at that event, not on wallets or an actor built earlier. The
reference is ash-template `AshTemplateWeb.Live.Session.check_component_events/2`
(branch `at/component-fresh-account`, e7ee597 until it reaches main).

1. **The page keeps its lease.** The `on_mount` that loads the person assigns
   `session_lease: nil`, and the code that holds a signed-in session assigns the lease
   it already re-reads on its own events (`%{lineage: ..., account_id: ...}`).
2. **One shared check.** The session module exposes a function that attaches a
   `:handle_event` hook to the component socket. LiveView allows `:handle_event`,
   `:after_render` and `:handle_async` hooks on components.
   - `lease: nil` (signed out): `{:cont, socket}`.
   - The lease still resolves (the same `leased_account/2` read the page uses):
     `{:cont, take_account.(socket, account)}` with the account that read returned.
     The check never reduces that account to a truth test.
   - Lapsed: `send(self(), {SessionModule, :component_lease_lapsed})` and
     `{:halt, %{}, socket}`. The empty reply answers reply-style events (a wallet
     step asked for gets nothing to send); the page's own `:handle_info` hook takes
     the message, re-reads the lease and withdraws the principal, so the page renders
     signed out. The component runs in the page's process, so `self()` is the page.
3. **Each component opts in** by calling the check first in `mount/1` with its own
   `take_account(socket, account)`, and assigns `lease` in every `update/2` clause
   that takes the page's assigns. A clause that picks fields (`Map.take`, pattern
   match) must name `lease`. `take_account` rebuilds everything the component acts
   with from the account (linked wallets, the actor, then any review built from
   them), and `update/2` calls the same function with the account the page passed,
   so there is one derivation, no second cache and no debounce. A component takes
   `account` from its page, never a prebuilt actor or wallet list.
4. **Every call site passes it:** `lease={@session_lease}`, through any function
   component in between (`attr :lease, :map, required: true`). A component given no
   lease fails on its first event instead of acting, so a missed call site shows at
   once. A page whose component acts for a stand-in account (a local lab) passes
   `lease={nil}`: the session is not the account it acts for.

Check: `grep -rl ":live_component" lib` lists every component; each one with a
`handle_event` that reads or writes for a person needs steps 3 and 4. Verify signed
out (events still answered), and with a scratch script, inside a transaction it rolls
back, that runs the component's hook with a nil, a lapsed and a current lease, then
changes the account's wallets and checks the next event sees them.

The page's disconnect broadcast on sign-out reaches only the node that handled it
unless the site's nodes are clustered; this check covers every event either way.

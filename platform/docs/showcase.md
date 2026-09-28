# Component workshop

The showcase setting (`ASH_TEMPLATE_SHOWCASE`, see the README's "Showcase"
section) decides who can open `/showcase`. In development it is `local`: open it
on a development server using `localhost` or `127.0.0.1`. HTTP requests and
connected page mounts both require a loopback peer and a loopback hostname;
forwarded headers do not grant access. Gallery styles and metadata use the same
guard. On the hosted demo it is `public`, and a new site's production sets it to
`off`, where the routes answer 404.

## What it shows

The workshop renders the active components installed from `regent_ui` and
`AshTemplateWeb.Components`, plus both layouts, composed in the shared
`Regent.Structure` frames, rows, section bars and panels. The shell preview
includes working navigation and theme behavior but omits sign-in controls.

Palette cards pair each site's light/dark colors with a real
surface/text/primary preview. Four editable colors (background, surface, text
and primary) are stored separately for each site/mode in browser storage; Reset
affects only the selected palette. The Shimmer color picker overrides
`--rg-shimmer-color` for the workshop document and resets on reload.

`Regent.Structure.capability_card/1` is the shared card, not workshop-specific
HTML. Its API, together with every component's attributes and slots, the
installed Ash domain/resource/action metadata and the exported utility APIs, is
listed at `/showcase/catalog`. The catalog never reads resource records.

## Privy working reference

`/showcase/privy` uses the real account control and auth bridge, not the
separate wallet fixture in the main gallery. It includes configuration
instructions, header Sign In/Disconnect, in-page connection controls and the
selected wallet. Controls are disabled with an explanation when configuration is
missing. No configuration values, tokens or
provider objects are displayed, and the page requests no transaction or extra
signature.

To sign in for real, use the configured development server and a Privy-allowed
localhost origin with `PRIVY_APP_ID` and `PRIVY_VERIFICATION_KEY` set. Prepare
the local database (`ash_template_dev`), run `mix ash_template.setup_local_auth`,
then `mix assets.build` and `mix phx.server`.

## Wallet buttons

`/showcase/wallet` runs `AshTemplateWeb.OnchainExample` exactly as a product
page would: the signed-in account's wallets from `AccessContext.linked_wallets/1`,
Privy's active wallet, and the chain from `:wallet_chain` (Base Sepolia). Every
press reaches the wallet; Record and Fail on purpose need a little Base Sepolia
test ETH for the network fee. `/showcase/onchain` is the same component against
a lab chain and a stand-in wallet on this machine, and exists only in `local`.

## Utility effects

- Wallet fixture: a separate local provider demonstrates connect/disconnect,
  overlapping presses, confirmation, rejection and revert. It never enters the
  real wallet store or sends a network request.
- Create/add/reset items and edits use a local Ash sample action with an
  in-memory data layer. Copy writes the displayed result through the browser
  clipboard API. These examples never write product records.
- Privy verification: signs an ephemeral fixture token and calls `RegentPrivy`
  for valid, expired and incorrect-audience outcomes. No fixture token enters an
  authentication endpoint; no key or token is displayed or retained.
- Postgres: a fixed read-only diagnostic accepts only the loopback development
  database `ash_template_dev`. It refuses other database settings, and the
  workshop shows it only in `local`.

---
name: ash-frontend
description: Build or refine AshPhoenix forms and LiveView interfaces.
---

# Ash Frontend

Keep domain behavior in the action and presentation in the component or LiveView.
Action-bound AshPhoenix forms are a supported boundary; do not add an Ecto changeset
pipeline around them. Verify generated helper signatures against the installed version.

- [Forms and LiveView](references/forms-and-liveview.md): validation/submission,
  nested forms, omitted inputs, async results and reconnect behavior.
- [Async state](references/async-state.md): reads owned by an account, wallet or
  route; late answers dropped; loading, ready, empty, stale and error kept apart.
  Every page read goes through the template's `Read`; never stop one with
  `cancel_async`, which takes the read's database connection down with it.
- [Public figures](references/public-figures.md): a figure every visitor sees
  alike is read once and shared by every open page, through the row's own
  publication or `AshTemplate.SharedReading`; quiet pages; memory for each open
  page.
- [UI review](references/ui-review.md): accessibility, responsive states and hooks.

## Regent UI conventions (founder, 2026-10-19)

Every Regent site follows these. The design-system `STYLE.md` sections named here hold
the detail.

- **Contract addresses and transaction hashes** always show the short form, then a copy
  icon and a diagonal arrow (up and to the right) that opens the address or transaction
  on Basescan in a new tab, the three tight together. They come from one shared
  component, never drawn by hand (STYLE.md, "Addresses and transaction hashes").
- **No default square dialogs.** Every modal or window uses the shared cut-corner shell:
  two cut corners with their accents and two decorated square corners, the primary
  button's treatment at panel size (STYLE.md, "Dialogs").
- **On-chain buttons:** signed out, the first press opens Privy's sign-in. Approve and
  the button it unlocks (Buy, Stake) are the same size. Once the approval's transaction
  succeeds, Approve turns grey with a green border and stays pressable. See
  [onchain-buttons](../onchain-buttons/SKILL.md).
- **Primary CTAs** use the site's primary colour and the shared CTA motion. The corner
  marks and accents appear on hover and keyboard focus; hover never takes them away.
  Two buttons side by side in a header never look the same: one primary, one secondary
  (STYLE.md, "Shape and spacing").

Every page with the side panel is a `ShellLive` action in `live_session :product_shell`;
a page never draws the shell itself, or signed in it shows half a side panel.

Reuse Regent UI primitives while retaining each product's theme, navigation and
layout. Components own no authentication, database or wallet admission decisions.
A second on-chain button press must still reach the wallet while the first is pending.

Keep the returned error form after failed submission. LiveView tests do not execute
browser hooks; use a browser when the changed behavior depends on JavaScript or layout.

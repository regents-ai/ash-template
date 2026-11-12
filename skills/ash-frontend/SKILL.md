---
name: ash-frontend
description: AshPhoenix forms and LiveView pages on Regent's sites - form validation and submission, nested forms, page reads through the template's Read, figures shared by every open page, loading, empty, stale and error states, and Regent's UI conventions (icons, dialogs, addresses, CTAs, the product shell). Use when building or changing a LiveView, form, component or page read, reviewing a page's states or accessibility, or debugging a form that loses input or a page that shows stale data.
---

# Ash frontend

Load `ash-stack` first. Domain behaviour stays in the action; presentation in the
component or LiveView. Action-bound AshPhoenix forms are the boundary: no Ecto
changeset pipeline around them, and generated helper signatures are checked against
the installed version.

## References

- [Forms and LiveView](references/forms-and-liveview.md): validation and submission,
  nested forms, omitted inputs, async results, reconnect.
- [Async state](references/async-state.md): reads owned by an account, wallet or
  route; late answers dropped; loading, ready, empty, stale and error kept apart.
  Every page read goes through the template's `Read`; never stop one with
  `cancel_async`, which takes the read's database connection down with it.
- [Public figures](references/public-figures.md): a figure every visitor sees alike is
  read once and shared by every open page, through the row's own publication or
  `AshTemplate.SharedReading`; quiet pages; memory for each open page.
- [UI review](references/ui-review.md): accessibility, responsive states, hooks.

## Regent UI conventions (Sean, 19 Oct)

`STYLE.md` in design-system holds the detail for each.

- **Icons** come from Lucide through `Regent.Icons.icon`, at the library's one line
  weight (5 Nov). Never draw an icon by hand in a site; logos and artwork are not
  icons. Look at a new icon zoomed 3-6x beside its neighbours for weight, height,
  baseline and colour: width checks do not catch this.
- **Contract addresses and transaction hashes** show the short form, then a copy icon
  and a diagonal arrow (up and to the right) that opens Basescan in a new tab, the three
  tight together, from the one shared component ("Addresses and transaction hashes").
- **Dialogs** use the shared cut-corner shell: two cut corners with their accents and
  two decorated square corners, the primary button's treatment at panel size. Never a
  default square dialog ("Dialogs").
- **Primary CTAs** use the site's primary colour and the shared CTA motion. Corner
  marks and accents appear on hover and keyboard focus; hover never takes them away.
  Two buttons side by side in a header never look the same: one primary, one secondary
  ("Shape and spacing").
- **On-chain buttons**: signed out, the first press opens Privy's sign-in. Approve and
  the button it unlocks are the same size; once the approval succeeds, Approve turns
  grey with a green border and stays pressable. A second press reaches the wallet
  while the first is pending ([onchain-buttons](../onchain-buttons/SKILL.md)).
- **Words**: no W-word openings, and titles of one or two words (regent-workflow,
  "Words on screen").
- **The product shell.** Every page with the account menu is a `ShellLive` action in
  `live_session :product_shell`. A page never draws the shell itself, or its account
  menu has no agents when signed in.
- **Reading pages.** Every page a person can reach from the site's own links opens
  inside the site's shell; reading pages (about, docs, changelog, agent guide, privacy,
  terms) use the shared reading view, never a separate bare layout. Machine reads at the
  same address (Markdown, JSON) are answers, not pages. The template's view is
  `AshTemplateWeb.Components.Reading`, a `ShellLive` action per address drawn from the
  committed Markdown its twin serves (founder, 12 Nov 2026).
- Reuse Regent UI primitives and keep each product's theme, navigation and layout.
  Components own no authentication, database or wallet admission decisions.
- Keep the returned error form after a failed submission.
- LiveView tests do not run hooks: use a browser when behaviour depends on JavaScript
  or layout.

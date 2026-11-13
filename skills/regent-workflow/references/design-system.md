# Shared Regent design and showcase contract

Use this reference for product UI changes across `repos/regents`, `repos/techtree`,
`repos/autolaunch`, `repos/patchbay`, `repos/keyfleet` and the template repository. The
current founder request overrides older rollout notes. Re-read the working tree: an accepted refinement may not yet be in HEAD.

## Ownership and sources

- `STYLE.md` on design-system's main describes the canonical visual language. Read it with
  `git -C repos/design-system show origin/main:STYLE.md`: the local checkout holds other
  sessions' work and can sit far behind main.
- `repos/design-system/design_system_tokens.css` owns palette and typography values.
  Generate mirrors with `node scripts/generate-tokens-json.mjs`; do not hand-edit
  generated JSON/CSS or a consumer's `assets/vendor/regent_ui/` copies.
- `repos/design-system/regent_ui/lib/regent/` owns shared Phoenix presentation
  components; `regent_ui/assets/css/` owns their styles. A repeated shared-control
  defect belongs here, not in four incompatible product overrides.
- Product `platform/` directories own page composition, routes, data, forms, events,
  permissions and wallet workflows. Keep those responsibilities out of `regent_ui`.
- `CONSUMERS.md` records which app uses which shared piece.
- Coordinate one writer per overlapping surface. Inspect current diffs and preserve
  dirty preimages; never reset, stash, or replace another thread's WIP to get a clean
  baseline. Compare a visual change against its preimage, not the whole dirty HEAD diff.

## Current visual defaults

- **Geist Serif, upright 400** for everything: titles, headings, body, navigation,
  controls, labels, addresses, hashes and amounts (Sean, 30 Oct 2026). Geist Mono only
  for code (`code`, `kbd`, `pre`, `samp`, pairing messages). Use the role tokens
  (`--font-family-title`, `--font-family-ui`, `--font-family-paragraph`, `--font-family-mono`
  for code), never a face name. Never synthesize bold: Vercel ships Serif in 400 only.
- Root brand IDs are `platform` (Regents), `techtree`, `autolaunch`, `patchbay`;
  mode IDs are `light` and `dark`. Preserve the eight canonical palette definitions
  and Patchbay aliases. Use paired supporting surface/ink roles rather than recoloring
  the whole page from an individual card.
- The root carries no `data-theme` until the person chooses on the site; the shared
  tokens then follow the device, dark unless it asks for light (founder, 2026-09-28).
  A choice travels in the `regent_theme` cookie and always wins. A product's own
  theme CSS covers the no-choice case too. The template's theme plug, root layout and
  `assets/js/theme.ts` are the reference; the theme switch names itself, so the
  server passes it no theme.
- The theme switch is the template's `Shell.theme_toggle/1` (Sean, 8 Nov 2026), not
  `Regent.ThemeToggle`: a `role="switch"` button named "Light theme", night (dark) on
  the left and day (light) on the right. Signed in it is a row of the account menu
  (`Regent.Account.menu`'s `theme` slot, words at the start, switch at the end); signed
  out, with no account menu, it is in the app shell's bottom bar; the public footer has
  its own. Never put it in the top bar. A press, Enter or Space turns it, and the theme
  changes on the press, never waiting for anything drawn. The control is a flat, square
  track and knob, with no shadow, glow or rounded corner; the knob is the theme's ink
  (`--color-fg`), so the lit sun and the moon stand at least 3:1 on it. Over the knob's
  way lies the particle field (`ParticleField.particle_field ... driven`, Sean, 12 Nov
  2026: "make them look good for light - dark switches"): the server draws the moon
  (Lucide's, filled, in the page colour) and the sun (Lucide's, its disc filled, in
  `--particle-lit`) as SVG, and the browser draws the same pictures in grains in the
  same place, so a new picture is an edit to those two SVGs in `Shell.theme_toggle/1`.
  A pointer press flies the grains between them in about 330 ms while the knob glides on
  the system's on-screen curve; a second press mid-flight turns them round; keys turn it
  at once. The grain count follows the canvas (`grainsFor`, 0.7 grains a device pixel),
  flat ink with no glow (only the lab asks for glow), and nothing is drawn while idle.
  Less motion, forced colours and no WebGPU keep the server's drawing.
- Canonical identities: Tangerine `#FF5B19`, Powder Blue `#AECACD`, Platinum
  `#E5E3D2`, Charcoal `#161616`. Typography/background/semantic roles still come from
  the tokens, not scattered literals. Do not replace real project images or site
  logos with decorative gradients without an explicit content-level request.
- Use ruled frames, aligned sections, generous spacing and flat square/cut skins.
  Clip only decorative layers; menus, interactive hosts and focus outlines stay visible.
  Circles remain appropriate for avatars and meaningful indicators.
- Shared selects reserve a **24px right chevron inset** and **48px text padding**;
  forced colors restores native appearance.
- Every page a person can reach from the site's own links opens inside the site's shell;
  reading pages (about, docs, changelog, agent guide, privacy, terms) use the shared
  reading view, never a separate bare layout. Machine reads at the same address
  (Markdown, JSON) are answers, not pages. The template's reading view
  (`AshTemplateWeb.Components.Reading`) is the reference: the document's title, then its
  prose at about 70 characters a line, with the section's list of documents in the
  shell's side menu (founder, 12 Nov 2026). The developer documentation's title row says
  Docs, as its menu link does, while its Markdown keeps its longer title (founder, 12 Nov
  2026).

## Primary buttons and card imagery

- Primary sheen is a restrained **orange-default VGPU-like color treatment in shared
  CSS**, not the old gray/blue wash. The button sheen itself is CSS, not a claim of
  GPU rendering. Labels are transparent: do not reintroduce an opaque rectangle.
- Primary links/buttons have **no underline**. Keep selectors strong enough to beat
  later prose-link hover rules without disabling ordinary text-link affordances.
- Dark resting primary controls use blue opposing corner marks and orange cut accents;
  light resting controls use two opposing orange corner edges. Hover/focus grows a
  full matching cut outline; settled entry and exit use **150ms** base transitions.
  Native CSS reversal shortening applies to interrupted transitions.
- `--rg-shimmer-color` customizes the sheen; `--rg-button-border-color` customizes the
  outline and falls back to the sheen color; `--rg-shimmer-duration` controls the base
  sweep. The base sweep is 1.15s; the capability card's edge ripple runs at twice that.
- Secondary/quiet/disabled controls do not become animated primaries. Reduced motion
  removes the sweep and makes outline state changes immediate; forced colors retains
  native system borders and separate keyboard focus.
- `.rg-button__label` is an optional transparent label wrapper, not mandatory markup
  for every CSS-only link. Preserve explicit inner layout for icon/text combinations.
  Do **not** blindly convert compound image/selection cards to a primary button: wrapping
  their children and changing cascade layers can collapse their artwork/grid. Native
  selectable cards are valid when they preserve the application action and composition.
- `Regent.Structure.capability_card` owns the shared title/media/description/action
  structure. It accepts image source/alt or custom media and caller-owned action slots.
  Keep decorative shader/media variation in the media layer, never over readable copy.
- `Regent.Structure.ratio_card` is read-only presentation. Its bounded integer basis
  points drive both percentages, ARIA and fill; `nil` means unknown, not zero. Product
  code must provide the correct denominator and existing data, never invented metrics.

## Preserve each homepage's purpose

- **Regents `/` and the template's `/`:** dark-only. The VGPU datascape fills the window
  and the page opens on the picture alone. Pressing a panel in the picture brings up one
  glass panel holding the header, the name and its line, the actions, the product tabs and
  the document links; two seconds after the last press, steering the picture shrinks it
  away until the next press. The copyright stands at the window's bottom right. Preserve
  the saved theme for other routes.
- **Techtree `/`:** preserve its actual VGPU 13-cube crown/lasers and existing light/dark
  material mapping. Keep the same content-first hero composition and its functional
  setup/release content. Do not replace the shader with an oversized static diagram.
- **Autolaunch `/`:** auction and token market listings remain primary content.
- **Patchbay `/`:** WebMCP site directory and message-board content remain primary.
- Generic page-background retirement is not permission to delete the Techtree crown hero
  or the homepage datascape. Bound artwork independently of text; reuse existing island visibility, resize,
  reduced-motion, device-loss and disposal behavior. Verify a completed real GPU frame,
  not merely the existence of a canvas or a WebGPU adapter.
- For Regents token-economics copy, reuse the actual `/stake` wording: eligible USDC
  deposits are allocated by stake share; REGENT emissions depend on onchain rate and
  inventory; wallet transactions require signatures. Do not invent APRs, allocations,
  guaranteed revenue, or universal distributions. Distinguish desired copy from copy
  already integrated into the homepage.
- The USDC in a person's signed-in Privy wallet is their **USDC Balance** on every site
  (founder, 2026-09-28). It arrives when they send USDC to their address or buy it by
  card in Privy's card window, and payments are signed from it. Regent holds no balance for anyone:
  never call it credit, a prepaid balance or an account balance, and never offer refunds
  or withdrawals of it.

## Showcase and delivery

- The real Regents `/showcase` renders shared Phoenix components plus product examples.
  It is local-only and compares brand/mode treatments; check it against the component
  table in `repos/design-system/STYLE.md`, since it does not render every component.
  A showcase-only CSS fix does not fix a product, and a static mock is not component
  acceptance. Keep the actual examples and event ownership intact.
- `scripts/render-structure-showcase.exs` in design-system creates the separate,
  ignored `.showcase/` static export from real components. Regenerate it when relevant;
  do not edit the exported HTML/CSS by hand.
- Consumers copy shared assets through `mix regent_ui.assets`, normally invoked by
  `mix assets.build`. A consumer takes a design-system change by moving its pinned
  commit in `mix.exs`.
  Verify the installed aliases before running them. Fonts are same-origin under
  `/fonts/regent-ui/` and must be allowed by the static server and page CSP.
- Rebuild each affected consumer after a shared change. A passing build does not refresh
  templates already loaded in a server; verify actual HTTP/LiveView content. Do not
  stop an unrelated or another thread's server to resolve stale rendering.
- Default local review ports requested by the founder: Regents 4000, Autolaunch 4002,
  Techtree 4004, Patchbay 4006. Check listeners and their cwd before starting duplicates.
  Inspect the launcher/config: some dev configs do not honor PORT directly. Preserve
  configured auth and existing data; fixture servers are not real-provider acceptance.
- Prioritize the running UI and founder review. Use focused compile/type/build checks
  and actual visual/interaction checks; do not rebuild a broad test-maintenance backlog.
  Recheck keyboard focus, mobile text wrapping, theme persistence and failure states.
  Scope temporary diagnostics separately from product code and genuine wallet canaries.
- Keep transient completion status, runtime PIDs and unfinished implementation details
  in a handoff/work record, not as timeless skill rules. Reconcile delayed agent reports
  against current source and newer founder corrections before acting on them.

For visual craft, also read `/Users/sean/.agents/skills/emil-design-eng/SKILL.md` and
canonical `ash-frontend` guidance. Retain the founder's explicit motion/design choices
when general design advice differs; keep auth/transaction semantics unchanged by polish.

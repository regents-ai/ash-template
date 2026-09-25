# Anime.js on a LiveView island

How Anime.js runs inside a Phoenix LiveView hook in Regent's Ash apps. Everything marked
**(lab)** was reproduced in a browser against phoenix_live_view 1.2.11 and animejs 4.5.0.

## Ownership

- The server owns state and markup. An Ash action decides the outcome; the LiveView
  renders it; the hook only moves pixels. An animation never decides, delays or stands
  in for a result.
- Celebrate a result only after the action returns. In `handle_event`, call the code
  interface or `AshPhoenix.Form.submit/2`; on `{:ok, _}` `push_event/3` the moment to the
  island; on `{:error, form}` assign the returned form (keep it, per ash-frontend).
- On-chain buttons are never gated by motion. Never await an animation before calling
  the wallet, never disable a button or set `pointer-events: none` while motion runs,
  and never skip or merge a second press because an animation is still playing.
  Feedback motion runs alongside the wallet call.
- `regent_ui` components ship no hooks. The product writes the hook and decides when it
  loads, how it handles reduced motion and how it tears down (`design-system/CONSUMERS.md`).
- The hook reads only what the server rendered for this viewer. Never put data in
  `data-*` that the viewer is not allowed to see just because the animation wants it.

## Where the code lives

| App | Hooks | Language | animejs |
| --- | --- | --- | --- |
| regents, keyfleet, the template | `platform/assets/js/hooks/*.ts`, named export, listed in `app.ts` `hooks` | TS, strict, `skipLibCheck` | pinned `4.5.0` in `platform/package.json` |
| autolaunch | `platform/assets/js/hooks/*.ts` | TS | not installed |
| techtree, patchbay | `app.js` / `assets/js/hooks/*.js` | JS; no TS gate | not installed |

- Adding the dependency: exact pin `"animejs": "4.5.0"` in the app's `package.json`
  (`platform/` for autolaunch, `platform/assets/` for techtree and patchbay), install with
  `npm`, commit the lockfile. Adding TypeScript islands to techtree or patchbay changes
  their pipeline; ask first.
- Import named functions from `"animejs"`; the esbuild `--bundle` build tree-shakes them.
  Regents, KeyFleet and the template cap `app.js` at 175 KiB gzip (`vitest.budgets.config.ts`).
- Type the hook's `this` the house way (see `hooks/infinite_scroll.ts`): a local type with
  `el`, the LiveView methods you call, and your own fields. Combine behaviours on one element
  with `composeHooks` from `assets/js/hook_composition.ts`.
- Colocated hooks (`<script :type={Phoenix.LiveView.ColocatedHook} name=".X">`) are plain
  JS inside HEEx. Keep Anime.js islands in `assets/js/hooks/*.ts`.
- Existing reference: `repos/regents/platform/assets/js/hooks/motion.ts` (ShellMotion) and
  `docs/design/founder-shell/motion-evidence.md`. Copy its cancellation and generation
  counter. Do not copy its Scope: it calls `animate()` outside `scope.add()`, so its
  `scope.revert()` does not cover those animations.

## Canonical hook (lab)

```ts
import {animate, createScope, stagger, type Scope} from "animejs"

type ReceiptRevealHook = {
  el: HTMLElement
  handleEvent(event: string, callback: (payload: {amount: string}) => void): void
  scope?: Scope
}

export const ReceiptReveal = {
  mounted(this: ReceiptRevealHook) {
    const scope = createScope({
      root: this.el,
      mediaQueries: {reduced: "(prefers-reduced-motion: reduce)"},
    })

    this.scope = scope.add(() => {
      const reduced = scope.matches.reduced

      animate("[data-reveal]", {
        opacity: {from: 0},
        y: reduced ? 0 : {from: 8},
        delay: reduced ? 0 : stagger(24),
        duration: reduced ? 120 : 210,
        ease: "out(4)",
      })

      scope.add("confirmed", () => {
        animate("[data-receipt-total]", {
          scale: reduced ? 1 : [1, 1.06, 1],
          duration: reduced ? 0 : 280,
          ease: "inOut(2)",
        })
      })
    })

    this.handleEvent("receipt:confirmed", () => this.scope?.methods.confirmed())
  },

  destroyed(this: ReceiptRevealHook) {
    this.scope?.revert()
  },
}
```

```heex
<section id="receipt" phx-hook="ReceiptReveal">
  <p data-reveal>Receipt</p>
  <p data-reveal>Staked <strong data-receipt-total>{@total}</strong></p>
</section>
```

Why it is shaped this way:
- One Scope per hook, rooted at `this.el`. Selectors inside it only match inside the island.
- `from` animations end on the element's natural, server-rendered state. When a later patch
  strips the inline style, nothing visible changes (lab). The page is fully readable
  without JavaScript because the server never renders `opacity: 0`.
- Server moments arrive by `push_event`, and `handleEvent` calls a Scope method. Methods
  run inside the Scope, so what they create is tracked and reverted (lab).
- Reference the `scope` constant, not the constructor's argument: the types declare that
  argument optional, so `self.add(...)` fails under `strict`.
- `destroyed` reverts everything; LiveView removes `handleEvent` callbacks itself.

## What a LiveView patch does to Anime.js's DOM writes

LiveView patches an element whenever its rendered output changes, including when an unrelated
assign re-renders the surrounding template (lab: a counter change ran `beforeUpdate`/`updated`
on an untouched list). Anything the server did not render is removed at that moment, so bugs
show up intermittently.

| Anime.js writes | On the next patch of that element | Use |
| --- | --- | --- |
| Inline `style` (`animate`, `utils.set`, draggable, layout, animatable) | Removed (lab) | End animations on the natural state; or add `phx-mounted={JS.ignore_attributes(["style"])}` to keep it (lab); or animate inside a `phx-update="ignore"` island |
| `data-layout-id` from `createLayout().record()` | Removed; Layout can't match old and new, marks the root as entering and nothing moves (lab) | Render `data-layout-id` from the server on the root and every child (lab) |
| `splitText` spans | Server text replaces them | `split.revert()` in `beforeUpdate`, `splitText()` again in `updated` (lab); or `phx-update="ignore"` when the server never changes the text |
| Elements appended by JS (clones, overlays) | Removed from a patched parent; kept in an ignored container (lab) | Remove them in `beforeUpdate` (ShellMotion does) or append into an ignored container |

`phx-update="ignore"` (needs a unique `id`): children are never patched; on the ignored element
itself only `data-*` attributes are updated, and `updated()` still runs (lab). That makes
`data-*` the input channel for a fully JS-owned island:

```heex
<div id="meter" phx-hook="Meter" phx-update="ignore" data-level={@level}>
  <div class="bar"></div>
</div>
```

```ts
updated(this: MeterHook) {
  this.scope?.methods.level(Number(this.el.dataset.level))
}
```

Never put a form inside `phx-update="ignore"`: AshPhoenix error rendering stops working.

## Lifecycle map

| LiveView callback | Anime.js work |
| --- | --- |
| `mounted` | `createScope({root: this.el, mediaQueries})`; read `data-*`; entrance; register methods; `handleEvent` |
| `beforeUpdate(toEl)` | `layout.record()`, `split.revert()`, remove JS-added nodes, snapshot geometry |
| `updated` | `layout.animate()`, `splitText()` again, re-read `data-*` and call Scope methods. Must be harmless when nothing relevant changed |
| `disconnected` / `reconnected` | Pause and resume long timelines or scroll observers if the island has them |
| `destroyed` | `scope.revert()` (plus `layout.revert()` / `split.revert()` if created outside the Scope) |

## Scope rules (library source + lab)

- An object joins a Scope only if it is created while that Scope is active: inside a
  constructor passed to `add`, `addOnce` or `keepTime`, or inside a `scope.methods.*` call.
  Work started later from `setTimeout`, a promise or a DOM listener set up in the
  constructor is not tracked; after `revert()` its inline styles stay behind (lab). Send
  that work through a Scope method, or wrap it in `scope.execute(() => ...)`.
- Each Scope method call adds its objects to the Scope, and nothing removes them until
  `refresh()` or `revert()` (lab: 1, 2, 3...). For a stream of server updates (a price tick,
  a progress value), create one `createAnimatable` in the constructor and call its setters.
- A media query change runs `refresh()`: everything reverts and the constructors run again.
  Wrap continuous timelines in `scope.keepTime(() => ...)` so they keep their place.
- Listeners you add yourself go in the constructor, and the constructor returns a cleanup
  function that removes them.

## Layout on server-driven lists (lab)

```heex
<ul id="queue" phx-hook="QueueLayout" data-layout-id="queue">
  <li :for={item <- @items} id={"queue-#{item.id}"} data-layout-id={"queue-#{item.id}"}>...</li>
</ul>
```

```ts
mounted(this: QueueHook) { this.layout = createLayout(this.el, {duration: 280, ease: "inOut(2)"}) },
beforeUpdate(this: QueueHook) { this.layout?.record() },
updated(this: QueueHook) { this.layout?.animate() },
destroyed(this: QueueHook) { this.layout?.revert() },
```

Reorders glide, inserted items fade in (`enterFrom`), and neighbours of a removed item slide
over. The removed item itself disappears immediately: LiveView deletes the node before
`updated`, and Layout only animates leaving elements that become `display: none` or
`visibility: hidden`. For a visible exit, first render the item with the `hidden` attribute
(Layout fades it out and its neighbours close the gap, lab), then drop it in a later render;
or use `phx-remove={JS.transition(...)}` (CSS). The same applies to stream deletes. Use the
stream DOM id as `data-layout-id`.

## Regent motion rules (design-system/STYLE.md)

- Animate `transform` and `opacity` only. Enters ease out, on-screen moves ease in-out.
  Tokens: `--duration-fast|base|slow` = 140/200/280 ms, `--ease-out` =
  `cubicBezier(0.23, 1, 0.32, 1)`, `--ease-in-out` = `cubicBezier(0.77, 0, 0.175, 1)`.
- No idle or decorative loops, no card lift, nothing that follows the pointer (the
  holographic card is the one exception).
- Keyboard-triggered UI does not animate.
- Reduced motion wins: no movement, layout swaps instantly, at most a short opacity fade.
  Read it from a Scope media query, or from `data-reduced-motion` where the shell provides it.
- Content is visible by default. Only hide something after the script has taken over.
- `splitText` keeps an accessible copy of the text by default; leave `accessible` on.
- Error text, costs and transaction outcomes stay visible. Never fade them out.

## Checks

- `npm run typecheck` and `npm test` from `platform/` (budget test included where present).
- Unit-test only real controller logic (cancellation, generation counters) through an
  injected driver, as `test/motion.test.ts` does. No smoke tests.
- LiveView tests do not run hooks. Check the route in a browser: the animation plays, a
  server patch afterwards leaves the right final state, the island's teardown leaves no
  stray styles, and reduced motion behaves.
- If the browser preview is hidden, the page gets no animation frames and every Anime.js
  animation stalls. For a console-only check, set `engine.pauseOnDocumentHidden = false`,
  `engine.useDefaultMainLoop = false` and call `engine.update()` on a 16 ms interval.
  Never ship that.

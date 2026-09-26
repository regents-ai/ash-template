---
name: animejs
description: Anime.js v4 (npm animejs) animation in Regent's Phoenix LiveView and Ash apps, written as TypeScript hook islands. Use when adding, changing or reviewing motion that uses animejs — animate, timelines, timers, stagger, easings and springs, splitText, SVG morph/draw/motion path, draggable, animatable, onScroll, auto layout, Scope, engine, utils, WAAPI or the three.js adapter — or any LiveView hook that animates server-rendered DOM.
---

# Anime.js

**Load `ash-stack` and `ash-frontend` first.** The island is presentation only; the Ash
action and the LiveView own state, markup, authorization and outcomes. Their rules win
wherever they touch this skill.

Target version: **animejs 4.5.0** (pinned in Regents, KeyFleet and the template). A 5.0 beta
exists; do not use it. v3 code (`anime({...})`, `easing: 'easeOutQuad'`,
`direction: 'alternate'`, `anime.timeline`) is obsolete: rewrite it to the v4 API in
[animation](references/animation.md) rather than mixing styles.

## Start here

1. Read [LiveView islands](references/liveview-islands.md) before writing a hook. It holds
   the standard motion kit every Regent site shares, the canonical hook, the rules for
   what survives a LiveView patch, the lifecycle map and Regent's motion rules. Its claims
   were reproduced in a browser. Reach for the kit first: most pages only need its markup.
2. Open the reference for the API you need (below). Each section names its docs path.
3. When exact wording, an edge case or a docs example matters, read the live page (run
   from this skill's folder):

   ```bash
   uv run scripts/animejs_docs.py --list layout
   uv run scripts/animejs_docs.py layout/layout-methods/record
   ```

   `--list [filter]` prints every docs page path; pass one or more paths (or full URLs) to
   print them as Markdown with the JavaScript example; add `--html` for the example markup.
4. When types matter, the installed declarations are authoritative:
   `platform/node_modules/animejs/dist/modules/**/*.d.ts`.

## References

| File | Covers |
| --- | --- |
| [liveview-islands.md](references/liveview-islands.md) | Hooks, Scope per island, patch survival, Layout on server lists, Ash results, wallet rule, design rules, checks |
| [animation.md](references/animation.md) | Install, imports, `animate()`: targets, properties, values, tween params, keyframes, playback, callbacks, methods; easings and springs |
| [timer-timeline.md](references/timer-timeline.md) | `createTimer`, `createTimeline`, time positions, labels, sync |
| [interaction.md](references/interaction.md) | `createAnimatable`, `createDraggable`, `onScroll` / ScrollObserver |
| [scope-engine-utils.md](references/scope-engine-utils.md) | `createScope`, `engine`, every `utils` helper including `stagger` |
| [svg-text-layout.md](references/svg-text-layout.md) | `svg.morphTo` / `createDrawable` / `createMotionPath`, `splitText`, `createLayout` |
| [waapi-adapters.md](references/waapi-adapters.md) | `waapi.animate()` and when to prefer it; the three.js adapter |

## Rules that always apply

- One `createScope({root: this.el})` per hook; create every Anime.js object inside its
  constructor or a Scope method; `scope.revert()` in `destroyed`.
- Server moments reach the island by `push_event` → `handleEvent` → Scope method, or by
  `data-*` attributes read in `updated`. Celebrate only after the Ash action succeeded.
- Anything Anime.js writes into server-rendered DOM (inline styles, `data-layout-id`,
  split spans, added nodes) is wiped by the next patch of that element. Design for it:
  end on the natural state, render layout ids from the server, revert-and-redo around
  patches, or isolate with `phx-update="ignore"` / `JS.ignore_attributes`.
- A move that hands its element back to the stylesheet starts with the kit's `play()`,
  so a move begun over another still ends at rest.
- On-chain buttons are never gated, delayed or deduplicated by motion. Every press
  reaches the wallet.
- Transform and opacity only, no idle loops, reduced motion wins, content visible
  without JavaScript, keyboard-triggered UI does not animate.
- LiveView tests do not run hooks. Prove motion in a browser, then run `npm run typecheck`
  and `npm test` in `platform/`.

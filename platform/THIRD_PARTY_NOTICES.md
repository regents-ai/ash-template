# Third-party notices

Third-party material redistributed inside this repository, and the terms it arrives under.

## vgpu — account holographic card

The foil on the account page's identity card and the homepage's feature cards is the shared `Regent.HolographicCard`
from the Regent design system, whose `holographic_card.mjs` adapts the "Holographic
Card" example published with Vercel's `vgpu` project. This repository ships no copy of
that material: `mix regent_ui.assets` stages the module from the pinned design-system
revision at build time, and the attribution and licence text live in the design system's
`THIRD_PARTY_NOTICES.md`. The renderer runs on the `vgpu` 0.3.1 this repository pins.

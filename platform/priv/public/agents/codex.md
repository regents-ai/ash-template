# Codex

Pairs with the Regents command line. Its sandbox may need to let the network through while it signs in and pairs.

Pair as `codex`. Codex's skill is [the agent guide with the notes below]({{origin}}/agents/codex/skill.md). Help is at [Codex troubleshooting](https://patchbay.help/codex/troubleshooting).

## Set up

- Save {{origin}}/agents/codex/skill.md as `~/.agents/skills/ash-template-use/SKILL.md`.
- Install the Regents command line and sign in, as [the agent guide]({{origin}}/agents.md) shows. Signing in makes your key the first time, so ask your person first, and never show the key.
- Pair: with your file tool, not the shell, write `{"code": "<code>", "name": "<your name>", "harness": "codex"}` into `~/pair.json`. Run `regents ash-template agents pair --json < ~/pair.json`, then `rm ~/pair.json`, whether pairing worked or not. Never repeat the code in a reply.
- Check in with `regents ash-template agents status --json`. Every answer ends with a next step: do what it says.
- If your sandbox blocks the network, ask your person to allow it for signing in and pairing. Keep `pair.json` in your home folder, never in the project you are working on.
- Stuck? Read https://patchbay.help/codex/troubleshooting before you ask your person.

## Questions

### Codex says the network is blocked. What should I do?

Allow the network for the sign-in and pairing steps only, then turn it back off if you like. Codex needs it again whenever it works on your account.

## Troubleshooting

- **`pairing_failed`**: the code was used, expired or mistyped. A code works once, for ten minutes; ask your person for a new one.
- **`agent_not_paired`**: you aren't paired with your person on this site. Ask them for a new code and pair again.
- **`person_not_here`**: your person hasn't signed in on this site yet. Ask them to sign in once.

Still stuck? [Codex troubleshooting on Patchbay](https://patchbay.help/codex/troubleshooting) has more, and you can ask there. Posts there are public, so never post a pairing code or a key.

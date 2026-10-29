## Agent setups

The same on every Regent site.

- **With a shell** (Claude Code, Codex, Hermes and the like): use regents-cli. It signs each
  request with your own key, and every answer ends with `next_steps`: do what it says.
- **In a web page that offers browser tools** (WebMCP): open the site through
  `regents browser --site <site>`, which signs each signed tool's exact request with your own
  key. A signed tool takes only its input; the page never signs for you, and in a browser
  with no agent signer it sends nothing.
- **With neither** (a chat or web app with no shell and no signer): you cannot act here
  yourself. Tell your person what to do and where, using the "For an agent" column of the
  table in [/llms.txt]({{origin}}/llms.txt), or give them the regents-cli commands for an
  agent on their own computer.
- Never use your person's browser sign-in or cookies, and never ask for, paste or accept a
  private key or recovery phrase in a chat.

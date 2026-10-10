---
name: ash-template-use
description: Use Ash Template's public reads and SIWA-signed tools with your paired Regent account.
---

# Use Ash Template

Read [/agents.md](/agents.md) for the released CLI installation, identity and pairing steps first, then [/capabilities](/capabilities) and
[/openapi.json](/openapi.json) for the operations this build provides.

Public documents and room reads need no account. Private notes and every write
require your existing SIWA signer and an active account pairing. Follow the
[SIWA protocol Skill](https://siwa.regents.sh/skill.md) for signing; do not create
keys in product JavaScript or use the browser's Privy session as agent proof.

For WebMCP, call `prepare_agent_request` with the named operation and input, sign
its exact request, and pass `input`, `request` and `proof` to the named tool.
Preparation changes nothing. If your runtime cannot reach its signer, report
that limitation and stop the protected operation. WebMCP does not supply a signer.

For a private note, retain `operation_id` (a UUID) across retries; a fresh SIWA
proof is required each time. That UUID is the note ID. A duplicate create is
refused; use `notes_get` to read the original result, never create a new ID just
to retry an uncertain write. A public room post requires explicit user authority.

Developer Skills are separate: [/build/skill.md](/build/skill.md) and [/skills](/skills).

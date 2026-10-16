# Bandit HTTP/2 security update — local only

CVE-2026-105659 (EEF-CVE-2026-105659 / GHSA-69m6-wcv4-rwcf) affects
Bandit 1.12.5. A client could keep a blocked HTTP/2 response alive with tiny
WINDOW_UPDATE increments or empty SETTINGS frames. Connection and stream send
windows both need the progress-based deadline fix.

On 14 October the template pinned the official upstream commit
`d88b21953c65061f21136ea76a89a4f95a2ac7a1`, because no fixed Hex release existed.
Bandit 1.13.0 and 1.13.1, published on 15 October, contain that commit. On 16 October
the template moved to Hex `{:bandit, "~> 1.13"}`, locked at 1.13.1, and the shared
required-fixes registry now requires Bandit 1.13.0 or later from Hex. No advisory is
suppressed.

The four upstream regression cases passed locally: connection-window byte
trickles, empty SETTINGS trickles, stream-window byte trickles, and a slow client
making sufficient progress. No product app, wallet or money worker was started
for those checks. Local verification does not update any deployed server.

Sources: [upstream advisory](https://github.com/mtrudel/bandit/security/advisories/GHSA-69m6-wcv4-rwcf)
and [official patch](https://github.com/mtrudel/bandit/commit/d88b21953c65061f21136ea76a89a4f95a2ac7a1).

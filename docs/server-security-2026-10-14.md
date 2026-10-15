# Bandit HTTP/2 security update — local only

CVE-2026-105659 (EEF-CVE-2026-105659 / GHSA-69m6-wcv4-rwcf) affects
Bandit 1.12.5. A client could keep a blocked HTTP/2 response alive with tiny
WINDOW_UPDATE increments or empty SETTINGS frames. Connection and stream send
windows both need the progress-based deadline fix.

The template pins the official upstream commit
`d88b21953c65061f21136ea76a89a4f95a2ac7a1`. Its application version still says
1.12.5; the locked Git source is the evidence of the fix. No fixed Hex release
was available when checked on 14 October. No advisory is suppressed. The shared
required-fixes registry enforces this source and commit ancestry for consumers.
When a fixed Hex version is available, replace the temporary managed Git entry
with a verified Hex minimum and update consumers together.

The four upstream regression cases passed locally: connection-window byte
trickles, empty SETTINGS trickles, stream-window byte trickles, and a slow client
making sufficient progress. No product app, wallet or money worker was started
for those checks. Local verification does not update any deployed server.

Sources: [upstream advisory](https://github.com/mtrudel/bandit/security/advisories/GHSA-69m6-wcv4-rwcf)
and [official patch](https://github.com/mtrudel/bandit/commit/d88b21953c65061f21136ea76a89a4f95a2ac7a1).

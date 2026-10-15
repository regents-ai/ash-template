# Connected-app sign-in: local reference

Sean authorized this bounded implementation on 14 October 2026: “Build the shared
Boruta/Privy service locally.” It does not authorize release or change the broader
connected-app backlog. OAuth defaults off (`ASH_TEMPLATE_OAUTH_ENABLED` is unset). The template has no hosted MCP endpoint;
its configured origin is a reference audience, not an advertised working tool URL.

`RegentOAuth` in `elixir-utils/oauth` supplies the Boruta 2.3.8 protocol adapter,
S256 PKCE, public-client registration, token refresh, consent and connected-app
revocation. The template supplies its verified Privy session and current canonical
account. Consent uses the browser pipeline's session authority and CSRF protection.
No request header or account parameter can establish a person. Nothing here grants
a paired-agent or wallet actor, and no new account store is introduced.

API routes expose resource/server metadata, `/oauth/register`, `/oauth/token` and
`/oauth/revoke`. Browser routes are GET/POST `/oauth/authorize`, GET
`/oauth/connections` and POST `/oauth/connections/revoke`. Credential routes disable
logging; the existing address limiter bounds registration and token requests.
A connected-app link is present on consent pages. There is no change to Account's
existing social-connections page.

A site adopts the adapter, router/controller wiring and supervised repo, supplies
its exact HTTPS issuer/resource and one event-read scope in config, and uses the
same literal issuer/resource in its additive migration. Tokens freeze that binding
at issuance. Never change a provider's audience by reinterpreting old rows.
The default issuer is `https://template.regents.sh`; the default resource is its
origin only because the template has no MCP route. Replace the resource before
turning the feature on. Do not add a dummy MCP route.

All shared packages use one reviewed `elixir-utils` Git commit, including OAuth.
The template's existing `REGENT_ELIXIR_UTILS_PATH` development override also covers
OAuth; production refuses that override. Normal local integration checks fetch the
exact pins from the local shared repository without changing the recorded URLs.
Publish the reviewed shared commit before a separately authorized consumer release
so its builds can fetch the exact pin.
Site-owned additive migrations create the OAuth tables; this change does not run
production migrations. Keep the feature off until the site has completed consent,
callback, refresh, disconnect and host checks.

Use Ash Signals for ordinary resource-change reactions where appropriate. They do
not replace an ordered, replayable MCP event log: write that log in the same
transaction as the domain action and use AshOban for delivery and retries. This
auth service adds no new domain-event producer, queue or polling loop. Patchbay's
existing committed event stream remains canonical.

Local checks use stand-in accounts and an isolated loopback database. They cannot
establish real Privy or ChatGPT acceptance. Money tests and Points activation are
outside this integration. Publishing and deployment require applicable authority;
live consent and event delivery require their own verification.

## Integration verified on 14 October

This reference is integrated against template main `905b1bee0c27ba61fafa4261e417fc9d5310a8e7`,
with all shared libraries pinned together at
`edb97f1c1bb7cc9ce1aa02f4646eea18f7f8923d`. The older primary checkout's
uncommitted draft is not the integrated reference.

Compilation, changed-file formatting, usage-rule synchronization, route handoff,
the dependency audit and the proposed required-fixes check passed. The actual
template session/consent routes were exercised against a named loopback database:
caller-supplied account IDs and stale sessions were refused; a current verified
account could consent and exchange its code. The additive migration ran only in
that local fixture. OAuth's default-off configuration and inactive Points were
checked separately.

Independent security review found and closed request-object input leakage,
cross-client revocation, refresh/revoke races and old revoked credentials affecting
fresh consent. Representative local checks covered each failure. The template
retains its existing Signals compiler and supervision; it adds no event producer.
See [the server security update](server-security-2026-10-14.md) for the Bandit fix.

## Consent browser repair — 15 October

The reference now carries shared commit
`28783ed77b4c6f5240f35a77146e06611abb23a6`, on the complete dependency baseline.
All Hex locks, the AshPostgres hold and the Bandit security pin remain unchanged.
OAuth remains off on the template, which has no MCP endpoint.

Consent uses the existing same-origin stylesheet and shared controls, with the
site's configured brand and theme. Only its consent document permits the
preauthorized registered callback origin in form-action; Chromium also checks
the redirect following approval. Other directives and independent browser
policies are preserved. Exact callback/account/scope/PKCE/CSRF/nonce/lifetime
checks remain required. Consumed or expired requests return a readable HTTP401
restart page, never a new grant.

The signed-cookie and actual-browser local exercise reproduced the old blocked
return and verified the corrected return to another origin. Independent security
review closed a combined-policy preservation finding. These are representative
checks, not real Privy/ChatGPT acceptance. Adopters must begin a fresh connection
from their client, then verify consent, token exchange, event subscription,
callback challenge, genuine delivery and unsubscribe separately. This correction
adds no migration, grant, queue or event producer. Money tests and Points stay off.

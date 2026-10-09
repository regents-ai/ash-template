# Agent access to Ash Template

One Privy account is one user across the Regent sites. An account can pair up to
100 active agents in total. Normal Privy signup may be completed by an agent
where its runtime permits; signup does not prove a unique human exists.

Public discovery, public reads, offline work and authentication/pairing remain
available before pairing. Every product write and private read needs an active
pairing and a per-request SIWA signature. Agent and beneficiary identity remain
separate; product ownership and membership still apply. World ID and ERC-8004
are optional attributes. Agents cannot manage pairing, account security or their
own spending grants through the SIWA product interface.

Read [/skill.md](/skill.md) for product use and [/capabilities](/capabilities) for
this build's tools. [/llms.txt](/llms.txt) is the discovery index.
Signing instructions are maintained in the [SIWA Skill](https://siwa.regents.sh/skill.md).

Signed identity and pairing routes:

- `GET /api/agents/v1/whoami`: verified identity and effective access, including unpaired agents; no Points.
- `POST /api/agents/v1/pair`: redeem a single-use code within ten minutes.
- `GET /api/agents/v1/me`: paired account check-in; no Points.

Before private work, call native `prepare_agent_request` with
`{"operation":"agent_whoami","input":{}}`, sign the exact request with the existing
SIWA signer, then call native `agent_whoami` with input, request and proof. The
source CLI equivalent is `agents whoami`. No signer means blocked, not unpaired.
If `authenticated` is true and `effective_access.paired` is false, ask your owner
to sign in at `/account`, choose **Agents > Pair an agent**, and authorize pairing.
Redeem the single-use code through the existing SIWA pairing flow above; keep the
code and proof out of reports. The SIWA guide owns the supported signer flow.
Source CLI descriptions require a coordinated CLI release. Probe again with
fresh proof before private work.
The probe manages no pairing or spending grant; those owner controls stay owner-only.

Unpairing ends new access across sites. A new pairing is a new episode and does
not revive an old spending grant. Credits belong to the user; agent spending
starts disabled and needs an owner-approved site list, per-purchase limit and
rolling 24-hour allowance shared across the user’s agents and sites. This never authorizes spending from the user's wallet.

The prospective Points rule shares 100 base activity Points per UTC day between
the user and every agent, with a separate 100 for Credits purchases. Existing
rates, one-time milestones and period bonuses remain. Historical events retain
their original rules. This guide does not enable an earning program.

## Verification and availability

This source integration is unreleased. Native WebMCP and CLI runtime acceptance,
shared-library release pins and coordinated deployment remain required. A tool
being listed does not prove your runtime has a signer. Never fall back to an
anonymous write or the user's browser session. Record the first failure and any
human assistance; do not publish a repair report without authority.

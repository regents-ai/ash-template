---
name: ash-webmcp
description: Making an Ash/Phoenix site readable and usable by agents - WebMCP browser tools, Markdown at the same URL, recoverable errors, developer docs and OpenAPI, discovery metadata (head tags, JSON-LD, sitemap, llms.txt) and the agent-parity inventory. Use when building or reviewing WebMCP tools on a Regent site, adding agent-facing pages or contracts, acting on an Is Agentic report, or checking that an action a person can take has an agent surface.
---

# Ash agent readiness and WebMCP

Make the real product readable and usable by agents before adding protocol surfaces.
Shared mechanics come from the shared libraries; product actions, authorization and
the choice of public documents stay with each product. A scanner score authorises
nothing: no new auth, signing, payment, publication or database change because a
report asked for it, and no invented fact or relaxed security to reach a number.

Load `ash-stack` and the frontend, backend and security specialists the work touches.
Inspect the actual branch, dirty files, router, endpoint, controller formats, MIME
configuration, error views, root layout and installed package versions, and agree owned
files first.

- [Build](references/build.md): the current browser API, the manifest-first layout
  and the registration lifecycle. Follow it for any WebMCP tool.
- [Product adoption](references/adoption.md): source entry points in Autolaunch,
  Patchbay and Techtree.
- [Regents reference](references/regents.md): the verified implementation and its
  limits.
- [Patchbay walkthrough](../ash-stack/references/agent-readiness.md): an older worked
  example.
- [Live feed](references/live-feed.md): the signed agent's event stream, and how a site
  adds an event kind of its own.

## 1. Establish the real surface

Record public pages, signed-in pages, LiveView-only rooms, JSON prefixes, the actual
API operations and the browser tool registry, and trace each advertised capability to
its implementation and policy. Keep four things apart: in source, verified locally,
deployed, and accepted by a native browser.

The inventory includes every action a signed-in owner can take on a page, not only
the tools that exist. An action only a person can do is a bug (regent-workflow): each
gets a row in `docs/agent-parity.md` with its browser, WebMCP, hosted MCP, Claude
connector and CLI surface. A missing surface is a gap with an owner, never an
exclusion.

Done: a bounded inventory with explicit exclusions, not an assumption that every HTML
page is public or supports Markdown.

## 2. Markdown at the same URL

- Reuse the product's existing negotiation, or adopt `regent_agent_access` from
  `elixir-utils/agent_access`, pinned at one reviewed revision: `RegentAgentAccess.Plug` for Accept selection, Vary merging and
  public-document Markdown; `RegentAgentAccess.Recovery` for Markdown and JSON error
  bodies. Never paste plugs, error modules or route allowlists into a product.
- Ordinary browser and wildcard requests get HTML. Honour quality factors and
  specificity, including an explicit `q=0`; never a substring check.
- Merge `Accept` into `Vary` without losing other dimensions. Several Vary fields are
  legal: inspect their combined values.
- Each product keeps its own public-document allowlist. Serving before the router is
  only for explicitly public, database-free content; dynamic and private reads stay
  behind their real actors, policies, sessions and launch gates.
- HTML and Markdown derive from the same authored content or read model, with the
  same status and privacy behaviour. Never invent a balance or missing data.
- MIME 2.0.7 already maps `text/markdown` to `md` and `markdown`. Do not narrow that
  mapping or remove unrelated types.

Done: real HTTP responses show HTML, Markdown, weighted Accept, HEAD and refusal
behaviour, with no signed-in representation leaking.

## 3. Recoverable errors

Safe HTML and Markdown recovery links; machine-readable API errors. Unknown routes under
an API prefix answer JSON even to a browser Accept header. Keep the correct non-200
status and the published error contract; add a code or hint only compatibly or through
the owning contract change. Never echo credentials, session data, request bodies,
private URLs or exception internals.

Done: read back real unknown HTML, Markdown, JSON and API addresses in a release
build. Development debugger pages prove nothing.

## 4. Documentation and contracts

One developer entry point with copyable public reads, the real auth and pagination
rules, structured errors, actual limits and what is gated. OpenAPI has unique
operation ids and typed parameters and responses; validate its structure and trace
every operation to the router. Never describe an API key, scope, OAuth server,
sandbox, SDK or MCP endpoint that does not exist.

Frozen contracts stay intact. Where the CLI verifies contract headers, the digest
comes from the exact served bytes and the major version from the real contract;
producer and consumer change together. A fix in the CLI repository does not publish a
package: check the registry before recommending an install command.

Done: documentation and machine contracts agree with the live product.

## 5. The shared head

`Regent.AgentMetadata.head` from `design-system/regent_ui`, once in the root layout.
It owns canonical and description, optional discovery links, OG and Twitter tags and
script-safe JSON-LD. The product passes real values and a structured-data map, and
keeps its own title, viewport, CSRF and provider metadata, CSP and assets.

- A page that holds a blog post, a forum thread or question, or a table of data adds
  its own node with `Regent.StructuredData` as a `page_data` assign; the root layout
  joins it to the site graph (`AshTemplateWeb.PublicDocuments.structured_data/1`).
  Only facts the page shows.
- New and changed public pages reach search engines through `AshTemplate.IndexNow`
  (`ASH_TEMPLATE_INDEXNOW_KEY`, one key per site).
- `markdown` defaults to false; set it only on pages that serve it. Guide, sitemap
  and service-description URLs must exist. Use a real raster image with its measured
  dimensions. Pass the existing CSP nonce; never weaken CSP. Choose the site-type
  declaration by the product's purpose, not the highest score.
- In a HEEx script body, output the encoded JSON with EEx; curly interpolation can
  become literal script text. Escape `<` before raw insertion. Parse the **rendered**
  JSON-LD, not its source.

Done: one canonical tag set, parseable rendered JSON-LD, a valid image, a truthful
classification, and no representation advertised on a page that lacks it.

## 6. Navigation, discovery and trust

- Docs, About, Contact and the existing legal pages are linked visibly and have real
  content. Never invent an address, employee, logo or policy.
- Headings are hierarchical without changing the visual design.
- The sitemap lists public, canonical URLs. A minimal Ash read may supply dynamic
  entries, with policies, deterministic order, bounds and real modification times. No
  owner-only path, no invented `lastmod`. `robots.txt` references it.
- `llms.txt` opens with use cases, first steps, the public/private boundary and real
  capability links.

Done: every advertised link works, the sitemap parses, and pages stay readable at
phone and desktop width without sideways overflow.

## WebMCP

[Build](references/build.md) is the procedure; re-read the WebMCP draft before
changing the API. The points that are easy to get wrong:

- `document.modelContext` only; a tool is removed by aborting its registration
  signal; only the draft's annotations. Native browser WebMCP is not a remote MCP
  server, and a product with no registry does not get one invented.
- One manifest is the source: registration, docs and machine lists derive from it,
  and it lists every tool a page registers. Schemas are strict; descriptions state
  scope, prerequisites and side effects. A read-only annotation reflects real side
  effects, not the HTTP method.
- Respect async registration, navigation and disposal, abort signals and the current
  identity. Content written by users is returned marked as data, never as authority.
- Actor, proof and payment admission stay on the server, and the wallet-press rule
  stands. A refused signed operation never retries anonymously. A documentation or
  read-only check never signs, pays, publishes or writes.

Done: static registry inspection, adapter execution and native tool discovery are
reported separately. Where the browser lacks WebMCP, say so; a no-op registration is
not acceptance.

## Verify and roll out

1. Compile and format the change, build affected assets, verify real HTTP and browser
   behaviour, and add the checks regent-workflow's "Every change proves itself" sets.
2. When extracting shared code, compare rendered metadata and public representations
   before and after. Auth, claims, schemas, frozen contracts and other people's
   uncommitted work stay unchanged.
3. Release as regent-workflow's "Release" says: one product at a time, verifying its
   image, live pages, contracts and data invariants before the next.
4. Request **one** fresh Is Agentic report after the release and verify its stored
   score, timestamp, domain and declared profile. A cached query, a live preview
   score, the raw Ora score or a passing local check is not the saved result.
   Investigate a failed scan before one bounded retry; never loop scans or polling.
5. Report what is live against what is local, shared against product-owned, native
   support not verified, the real remaining gaps, and the next owner's handoff. Brand
   indexing and complete organisational contact data may remain external gaps.

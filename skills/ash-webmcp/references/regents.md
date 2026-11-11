# Verified Regents reference

## Public result and limits

The saved Is Agentic report at
https://is-agentic.com/api/v1/report?url=regents.sh returned **98/100** with
`scanned_at: 2026-09-17T08:06:46.676Z`, after the Regents-only production release
`5417287311114a7bd5e5b98bdfe2bd30fefe8522`. The marketing/lab homepage declares
Business. This is not a claim that all App/API checks pass, nor a security audit.
Brand search and fuller organizational schema remained real limitations; no postal
address, auth protocol or MCP server was fabricated to obtain the score.

The earlier fully encoded API query returned an older stored result. Verify the
returned timestamp and canonical target, not the spelling of one cached request.
The public stream emits a raw Ora score as well as archive information; that raw
number is not Is Agentic's normalized score. Wait for the stored final report.

Local evidence is under workspace `artifacts/regents-agent-readiness/`. Its release
manifest identifies all staged sources/shared pins. Public-page and owner-mapping
readbacks were separate from browser rendering and schema validation. No test
database was created. Do not put owner records or credentials into skill examples.

## Source map

Relative to `repos/regents` on main:

| Behavior | Source |
| --- | --- |
| Accept selection, Vary merging, public-document Markdown, recovery bodies | shared `elixir-utils/agent_access` (`RegentAgentAccess`), plugged in `platform/lib/regents_web/endpoint.ex` |
| Public sources, configured origin, schema and sitemap data | `platform/lib/regents_web/public_documents.ex` |
| Docs/trust/discovery responses | `platform/lib/regents_web/controllers/public_pages_controller.ex` |
| Authoritative public Markdown and read-API definition | `platform/priv/public/` |
| Safe missing-page responses | `platform/lib/regents_web/controllers/error_html.ex`, `error_md.ex`, `error_json.ex` |
| Actual route/pipeline ownership | `platform/lib/regents_web/router.ex` |
| Shared metadata consumer | `platform/lib/regents_web/components/layouts/root.html.heex` |
| Frozen YAML contract headers | Sent by the route that serves the contract, as the template's `api_contract/2` in `AshTemplateWeb.PublicPagesController` does; never a plug in front of the static files |
| The CLI's pinned copies of each site's contracts, with their sha256 | `scripts/sync_platforms.py` and `platforms.lock.json` in `regents-cli` |

The shared head is `repos/design-system/regent_ui/lib/regent/agent_metadata.ex`, on
design-system main; Regents' root layout consumes it on main.

## Non-transferable product details

Regents projects only its explicit public documents before the router; the documents
are database-free. That placement is not a template for authenticated/database-backed
pages in other products. Its claims API is owner-authorized historical data, not an
anonymous ownership lookup or proof of current token holdings.

Keep the existing YAML bytes separate from the new documented read-only OpenAPI
scope. Header major/digest describe the actual YAML. Aligning source and headers does
not publish a CLI package or establish every CLI command's production acceptance.

The shared head consumes the product's structured-data map and capability flags.
Metadata encoding is reusable; entity facts, route allowlists, deployment pins,
identity policies and native tool registration are not implicitly transferred.

# Ash Template platform

This is the Phoenix/Ash component of the Ash Template monorepo. Run Mix and npm
here. `lib/ash_template/` owns domains; `lib/ash_template_web/` owns routes and
live pages. `contracts/` holds the OpenAPI contract, synced to `priv/static/`
with `mix ash_template.sync_api_contract`.

<!-- template-only -->
Keep the placeholder names until `scripts/init.sh` renames them.
<!-- /template-only -->

Follow the root instructions and the workspace's `regent-workflow`. Use the
assignment's acceptance and applicable focused checks. Browser fixtures belong to
the prepared local database. Shared dependencies (`design-system/regent_ui`,
`elixir-utils` privy, agent_access, format and credo_ash, `regents/identity`) are
git dependencies pinned to one commit each in `mix.exs`.

Every page's content security policy lives in
`lib/ash_template_web/content_security_policy.ex`; add an exact origin to the
one profile that needs it, never a wildcard or `'unsafe-eval'`. Rate limits key
on `AshTemplateWeb.ClientAddress`, and metrics are served only on the private
port. The README's "Security profiles" section explains all three.

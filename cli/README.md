# Ash Template commands

`commands.json` describes every command the `regents` command line runs against this
site: `regents ash-template health`, and so on. The code that runs them lives in
[regents-cli](https://github.com/regents-ai/regents-cli), which publishes the one
`@regentslabs/cli` package for every Regent site and pins this file by commit.

Each command names the route it calls and the operation in this site's OpenAPI
document that answers it, who may call it (`authority`) and what it changes
(`effect`). The format is
[`schemas/commands.v1.json`](https://github.com/regents-ai/regents-cli/blob/main/schemas/commands.v1.json);
its descriptions explain every field.

## Changing a command

Change `commands.json` in the same commit as the route it describes, then check it:

```sh
make check-cli
```

The check fetches regents-cli's checker and schema from GitHub at the commit
`REGENTS_CLI_REV` in the root `Makefile` pins (it needs `gh auth login`); move that
pin in a commit to take a newer format. It fails when the file does not fit the
format, or when a command's operation, method or path is not in
`platform/priv/public/openapi.json` or `platform/priv/static/api-contract.openapiv3.yaml`.

Then pin the new commit in `regents-cli`'s `platforms.lock.json`.

## What does not go here

- The shared profile commands. Every site serves the same profile, so they are
  `regents profile get|sync|update --base-url <this site>` in `regents-cli`.
- Browser sign-in, which has no command.

## A command with inputs

A list with filters and pages, from Autolaunch:

```json
{
  "command": "auctions list",
  "description": "List stored public auctions.",
  "operation_id": "listAuctions",
  "webmcp": "autolaunch_auctions",
  "method": "GET",
  "path": "/api/v1/auctions",
  "authority": "public",
  "effect": "read",
  "flags": [
    {"name": "mode", "type": "string", "in": "query", "field": "mode", "enum": ["all", "live"], "description": "Which auctions to list."},
    {"name": "after", "type": "string", "in": "query", "field": "after", "description": "The next_cursor from the previous page."}
  ],
  "pagination": {"has_more": "pagination.has_more", "cursor": "pagination.next_cursor", "flag": "after"}
}
```

A word in angle brackets (`auction <id>`) is an argument, listed under `arguments`
with the path parameter it fills.

Replace `base_url` with the site's address when the product gets one.

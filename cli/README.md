# Ash Template commands

`commands.json` describes every command the `regents` command line runs against this site:
`regents ash-template health`, and so on. The code that runs them lives in
[regents-cli](https://github.com/regents-ai/regents-cli), which publishes the one
`regents-cli` package for every Regent site and pins each site's file by commit. regents-cli
1.10.1 carries this site; each Regent site copies the same pattern for its own commands.

Each command names the route it calls and the operation in this site's OpenAPI
document that answers it, who may call it (`authority`) and what it changes
(`effect`). The format is
[`src/regents_cli/schemas/commands.v1.json`](https://github.com/regents-ai/regents-cli/blob/main/src/regents_cli/schemas/commands.v1.json);
its descriptions explain every field.

## Changing a command

1. **Docs first.** Write the change in [COMMANDS.md](COMMANDS.md): what the command does,
   its arguments and stdin, an example, its answer and its refusals, and a dated line under
   Changes when callers must change something. A command that is not described there does
   not exist yet.
2. **Build it in one commit:** the route, its operation in the OpenAPI documents and the
   `commands.json` entry together.
3. **Check it** from the repository root:

   ```sh
   make check-cli
   ```

   The check runs regents-cli's checker with `uv`, straight from GitHub at the commit
   `REGENTS_CLI_REV` in the root `Makefile` pins; move that pin in a commit to take a newer
   format. It fails when the file does not fit the format, or when a command's operation,
   method or path is not in `platform/priv/public/openapi.json` or
   `platform/priv/static/api-contract.openapiv3.yaml`.
4. **Send the change note.** Once the route is on main, send this note to the regents-cli
   chief, who moves the pin, tries each changed command and releases.

   ```text
   Site: ash-template
   Commit on main: <full commit> (live: yes or no)
   Added: <command words, or none>
   Changed: <command words - what is different, in plain words, or none>
   Removed: <command words, or none>
   For callers: <what someone already running it must change, or nothing>
   Docs: cli/COMMANDS.md#<section>
   ```

## What does not go here

- Browser sign-in, which has no command.
- Muting in rooms, and chat with the assistant, which stay on the website.

## A command that signs

`rooms post <room>` shows a command that changes something. Its `authority` is
`wallet-proof`: the agent signs in once with `regents auth login --site ash-template`, and
the command line signs every request with the agent's key. The site checks each request with
the shared sign-in service (`AshTemplateWeb.Plugs.AgentWallet`) and posts for the person the
agent is paired with, marked with the agent. `stdin_fields` names the body fields read from
stdin as one JSON object, here `{"body": "…", "operation_id": "<UUID>"}`.

## A command with inputs

`rooms messages <room>` in `commands.json` shows each kind of input: a word in angle
brackets is an argument, listed under `arguments` with the path parameter it fills;
`--limit` and `--after` are flags placed in the query; and `pagination` tells the command
line where the answer says whether another page follows and which flag asks for it.

Set `base_url` to the site's own address; the template's is its demo, template.regents.sh.

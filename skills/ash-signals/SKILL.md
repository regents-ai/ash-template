---
name: ash-signals
description: Adopting Ash signals on a Regent Phoenix and Ash site the way ash-template does, so one resource announces what happened and other resources react inside the same transaction. Use when moving a site to Ash 3.36 and AshOban 0.10, replacing Regent Credits' on_credited setting, wiring Points, mention notifications or other follow-up work to something a person did, or adding a signal or a listener.
---

# Ash signals

**Load `ash-stack` and `elixir-stack` first.** Whether a reaction is a signal, a direct
call, an AshOban trigger, a notifier or an ordered event log is the table in `ash-backend`
[Integrations](../ash-backend/references/integrations.md#when-one-resources-action-should-make-another-react).
This skill covers the signals: the template's signals and listeners, how a site adopts
them, and the rules for writing new ones. ash-template (`platform/lib/ash_template/`) is
the model. A site copies it and never grows its own variant. A change to a shared
signal starts in elixir-utils and the template, then, once Sean signs it off, goes to
all five sites at once (regent-workflow, "Shared changes").

## What the template has

| Signal module | Signal and fields | Emitted by | Heard by |
| --- | --- | --- | --- |
| `AshTemplate.Rooms.Signals` | `:message_posted` (`message_id`) | `Rooms.Message` `:post` | `Activity.Notification` `:notify_mentions`, which runs `NotifyMentions` |
| `AshTemplate.Notes.Signals` | `:note_saved` (`note_id`) | `Notes.Note` `:create` and `:update`, while the server can ask Jev | `Notes.Decision` `:request_label`, which runs `RequestLabel` |
| `AshTemplate.Notes.Signals` | `:note_created` (`note_id`, `changed_by_agent_id`) | `Notes.Note` `:create` | `Points.Award` `:agent_note` |
| `AshTemplate.Notes.Signals` | `:note_committed` (`note_id`), `phase :after_transaction` | `Notes.Note` `:create`, `emit ..., phase: :after_transaction`, only once the create has committed | `Journey.Value` `:note_created`, which writes the site's value step in the visit log |
| `RegentCredits.Signals` (elixir-utils `credits`) | `:purchase_credited`, `:purchase_attributed` (`purchase_id`, `privy_user_id`) | `RegentCredits.Purchase`, when a purchase is credited or a waiting one finds its account | `Points.Award` `:credits_purchase` |

Every listener uses the default inline delivery. For a signal in the default
`:after_action` phase, its work commits with the action that emitted the signal, and a
listener that fails rolls that action back. `:note_committed` is declared and emitted in
the `:after_transaction` phase: Ash emits it only once the action answered
`{:ok, record}`, after the commit, so its listener sees only committed work and must never
fail (a failing one turns the committed action's answer into an error). Use that phase
for a reaction that must not happen for rolled-back work and changes nothing, such as a
log line. The template has no job-delivered listener yet.

## Adopt it in a site, in this order

1. **Versions.** Set `{:ash, "~> 3.36"}` and `{:ash_oban, "~> 0.10.0"}`; Oban stays on 2.24.
   Pin elixir-utils to the commit the template pins, at or after `9db13eb`. That is
   where the Ash libraries move to 3.36 and Credits starts sending signals. Never pin
   ahead of the template on your own: a library commit that adds a shared table waits
   for that table to exist in the shared database. After moving the pin, force-compile
   the shared libraries in both dev and test.
2. **Compiler.** In `mix.exs`, set `compilers: [:ash_signals, :phoenix_live_view] ++ Mix.compilers()`.
   In `config/dev.exs`, give the endpoint
   `reloadable_compilers: [:ash_signals, :phoenix_live_view, :elixir, :app]`. With the
   template's `usage_rules` setting in `mix.exs`, `mix usage_rules.sync` then links Ash's
   own signals rules from `AGENTS.md`.
3. **Credits.** Delete the site's `on_credited` module, its `config :regent_credits,
   on_credited:` line and anything that names them. The setting no longer exists in the
   library. In the site's own Points domain, add a copy of `AshTemplate.Points.Award`
   (below), and list that domain in the site's Ash domains. Every site that lists
   `RegentCredits` may credit any purchase, so every site needs this listener.
4. **Site events.** Look for any change module that writes another resource's rows
   (a mention notifier, a "points for this" change, a follow-up record). Move each one to
   the template's shape:
   - declare the signal in `<Domain>.Signals`;
   - `emit` it from the action;
   - put the work in a generic action, on the resource that owns the result, under
     `signals_in`;
   - delete the old change module.
5. **Policies.** Give each listener action its own policy, with a comment saying it is
   reached only through the signal, after the emitting action was allowed. Writes that
   are the site's own bookkeeping use the system actor. A listener that acts for the
   person passes the emitting context on, the way `RequestLabel` calls
   `Ash.Context.to_opts(context)`, so the person's own limits and policies still apply.
6. **Check.** Run the site's full gate. Then walk the flows in the local site:
   - a room post that mentions someone gives that person one notification, and a
     self-mention gives none;
   - a refused post leaves no notification;
   - a note save asks for a label;
   - a credited purchase offers Points once. While the Points rule is off, nothing is
     queued.

## A listener, from the template

```elixir
defmodule AshTemplate.Points.Award do
  use Ash.Resource, domain: AshTemplate.Points, authorizers: [Ash.Policy.Authorizer]

  signals_in do
    from AshTemplate.Notes.Signals do
      on :note_created, :agent_note
    end

    from RegentCredits.Signals do
      on :purchase_credited, :purchase_credited, action: :credits_purchase
      on :purchase_attributed, :purchase_attributed, action: :credits_purchase
    end
  end

  actions do
    action :credits_purchase do
      argument :signal, :struct, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        record(%{
          rule_id: "credits.purchase_settled",
          source_app: "regents",
          source_kind: "credits_purchase",
          source_event_key: signal.purchase_id
        })
      end
    end

    # :agent_note, and record/1 calling RegentPoints.record_event/2 as the
    # system actor, are in the template's file.
  end

  policies do
    # Reached only through the signals above, after the action that emitted
    # them was allowed; each records as the system, never as the actor.
    policy always() do
      authorize_if always()
    end
  end
end
```

The emitting side is one line in the action:
`emit AshTemplate.Rooms.Signals, :message_posted, fields: [message_id: :id]`. A signal field
with the same name as one of the record's attributes is filled in without being listed
(`changed_by_agent_id` on `:note_created`).

## Rules (ash-template, 14 October 2026)

- Declare signals in one signal module per domain. The emitter and its listeners depend
  on that module, never on each other. Keep payloads small: send ids, not records. The
  listener reads what it needs.
- The listener owns its reaction: Activity writes the mention notifications and Points
  records points. The emitting resource names neither.
- Inline listeners run with the emitter's actor and `authorize?`, so the listener's
  policy must allow that actor.
- A listener returns nothing the emitter needs. A bulk write inside a listener passes
  `notify?: true`, and Ash sends the notices once the outer transaction commits. Do not
  return notifications from the listener.
- A job delivery (`on ..., delivery: {AshOban.Signals, queue: ...}`) stores the actor,
  so a site needs an actor persister first: a module implementing `AshOban.PersistActor`,
  set with `config :ash_oban, :actor_persister`. Job delivery commits with the action
  only when the emitter and Oban use the same Repo and the signal is emitted
  `:after_action`.
- `signal_id` is not a business key. An effect that must happen once still keys on the
  record: Points' `source_event_key` is the note or purchase id.
- Before renaming or removing a signal, one of its fields or a job-delivered listener,
  drain its queued jobs or give the listener an `upgrader`.
- A shared library emits its own signals (`RegentCredits.Signals`), and each site
  listens with a resource of its own. No library ships a listener that runs on every site.
- Pages still hear about changes through `Ash.Notifier.PubSub`; a signal does not
  replace it. A person's on-chain action is never queued, deferred or deduplicated
  through a signal (`regent-workflow`).
- Tests use `Ash.Signals.Test` (`assert_emits_signal/4`) where a rule depends on the
  signal, as `regent-workflow` ("Every change proves itself") sets out.

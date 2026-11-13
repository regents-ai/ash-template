---
name: ash-signals
description: Adopting Ash signals on a Regent Phoenix and Ash site the way ash-template does, so one resource announces what happened and other resources react inside the same transaction. Use when moving a site to Ash 3.36 and AshOban 0.10, wiring Points, mention notifications or other follow-up work to something a person did, or adding a signal or a listener.
---

# Ash signals

**Load `ash-stack` and `elixir-stack` first.** Whether a reaction is a signal, a direct
call, an AshOban trigger, a notifier or an ordered event log is the table in `ash-backend`
[Integrations](../ash-backend/references/integrations.md#when-one-resources-action-should-make-another-react).
This skill covers the signals: the template's signals and listeners, how a site adopts
them, and the rules for writing new ones. ash-template (`platform/lib/ash_template/`) is
the model. A site copies it and never grows its own variant. A change to a shared
signal starts in elixir-utils and the template, then, once the template's check is
clean, goes to all five sites at once (regent-workflow, "Shared changes").

## What the template has

| Signal module | Signal and fields | Emitted by | Heard by |
| --- | --- | --- | --- |
| `AshTemplate.Rooms.Signals` | `:message_posted` (`message_id`) | `Rooms.Message` `:post` | `Activity.Notification` `:notify_mentions`, which runs `NotifyMentions` |
| `AshTemplate.Notes.Signals` | `:note_saved` (`note_id`) | `Notes.Note` `:create` and `:update`, while the server can ask Jev | `Notes.Decision` `:request_label`, a job in the `default` queue that asks for a label once the save has committed |
| `AshTemplate.Notes.Signals` | `:note_created` (`note_id`, `changed_by_agent_id`) | `Notes.Note` `:create` | `Points.Award` `:agent_note` |
| `AshTemplate.Notes.Signals` | `:note_committed` (`note_id`), `phase :after_transaction` | `Notes.Note` `:create`, `emit ..., phase: :after_transaction`, only once the create has committed | No listener. The visit log writes the value step from Ash's `[:ash, :signal, :emitted]` telemetry (`AshTemplateWeb.VisitLog.Events`) |
| `AshTemplate.Accounts.Signals` | `:account_registered` (`account_id`) | `Accounts.HumanAccount` `:register_verified`, only when the sign-in inserted the account (a dynamic emit that reads Ash's `upsert_skipped`) | `Points.Award` `:account_registered` |
| `AshTemplate.Accounts.Signals` | `:social_linked` (`provider`, `subject`) | `Accounts.LinkedIdentity` `:upsert_verified`, which a sign-in reaches only for a subject new to the account | `Points.Award` `:social_linked` |
| `RegentAgents.Signals` (elixir-utils `agents`) | `:agent_paired` (`paired_agent_id`, `privy_user_id`) | `RegentAgents.PairedAgent` `:record` | `Points.Award` `:agent_paired` |

Every listener but one uses the default inline delivery. Its work commits with the
action that emitted the signal, and a listener that fails rolls that action back.
`Notes.Decision` `:request_label` is delivered as a job, because it takes the site-wide
lock on the day's questions: AshOban queues the job in the save's transaction, so a
save that rolls back asks nothing, and the job takes the lock in its own short
transaction once the save has committed.

A log line about something that must have happened, such as the site's value step,
comes from a signal in the `:after_transaction` phase, declared on the signal and on its
`emit`. Ash emits it only once the action answered `{:ok, record}`, after the commit, and
reports each emit as `[:ash, :signal, :emitted]` telemetry whether or not anything
listens. A telemetry handler writes the line; no resource listens just to log. Each site
emits one such signal for its value action and maps it to its name in
`AshTemplateWeb.VisitLog.values/0`.

## Adopt it in a site, in this order

1. **Versions.** Set `{:ash, "~> 3.36"}` and `{:ash_oban, "~> 0.10.0"}`; Oban stays on 2.24.
   Pin elixir-utils to the commit the template pins, at or after `9db13eb`. That is
   where the Ash libraries move to 3.36 and the shared libraries start sending signals. Never pin
   ahead of the template on your own: a library commit that adds a shared table waits
   for that table to exist in the shared database. After moving the pin, force-compile
   the shared libraries in both dev and test.
2. **Compiler.** In `mix.exs`, set `compilers: [:ash_signals, :phoenix_live_view] ++ Mix.compilers()`.
   In `config/dev.exs`, give the endpoint
   `reloadable_compilers: [:ash_signals, :phoenix_live_view, :elixir, :app]`. With the
   template's `usage_rules` setting in `mix.exs`, `mix usage_rules.sync` then links Ash's
   own signals rules from `AGENTS.md`.
3. **Points.** In the site's own Points domain, add a copy of `AshTemplate.Points.Award`
   (below), and list that domain in the site's Ash domains. Every site may pair an agent
   or register an account, so every site needs this listener.
4. **Site events.** Look for any change module that writes another resource's rows
   (a mention notifier, a "points for this" change, a follow-up record). Move each one to
   the template's shape:
   - declare the signal in `<Domain>.Signals`;
   - `emit` it from the action;
   - put the work in a generic action, on the resource that owns the result, under
     `signals_in`;
   - delete the old change module.
5. **Policies.** Give each listener action its own policy, with a comment saying it runs
   only as the signal's listener, after the emitting action was allowed. A listener that
   does the site's own bookkeeping admits its signal alone,
   `authorize_if signal_in(<Domain>.Signals, :<signal>)`, as `Activity.Notification`
   `:notify_mentions` does, so nothing calls it directly; a check on the system actor
   would refuse it, since it runs as whoever emitted the signal. Its writes use the
   system actor. A listener that acts for the person passes the emitting context on, the
   way `Notes.Decision` `:request_label` calls `Ash.Context.to_opts(context)`, so the
   person's own limits and policies still apply.
6. **Check.** Run the site's full gate. Then walk the flows in the local site:
   - a room post that mentions someone gives that person one notification, and a
     self-mention gives none;
   - a refused post leaves no notification;
   - a note save asks for a label;
   - a pairing offers Points once. While the Points rule is off, nothing is queued.

## A listener, from the template

```elixir
defmodule AshTemplate.Points.Award do
  use Ash.Resource, domain: AshTemplate.Points, authorizers: [Ash.Policy.Authorizer]

  signals_in do
    from AshTemplate.Notes.Signals do
      on :note_created, :agent_note
    end

    from RegentAgents.Signals do
      on :agent_paired, :agent_paired
    end
  end

  actions do
    action :agent_paired do
      argument :signal, RegentAgents.Signals.AgentPaired, allow_nil?: false

      run fn %{arguments: %{signal: signal}}, _context ->
        record(%{
          rule_id: "agent.activated",
          source_app: AshTemplate.site(),
          source_kind: "pairing",
          source_event_key: signal.paired_agent_id
        })
      end
    end

    # :agent_note, and record/1 calling RegentPoints.record_event/2 as the
    # system actor, are in the template's file.
  end

  policies do
    # Runs only as the listener of the signals above, after the action that
    # emitted them was allowed; each records as the system, never as the actor.
    policy action(:agent_paired) do
      authorize_if signal_in(RegentAgents.Signals, :agent_paired)
    end

    policy action(:agent_note) do
      authorize_if signal_in(AshTemplate.Notes.Signals, :note_created)
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
  on that module, never on each other. Keep payloads small: send ids, and a field a
  listener decides on before reading (a post's words, for mentions), never records. The
  listener reads what it needs.
- An inline listener runs inside the emitter's transaction and holds its connection and
  row locks until commit, so it does only work of fixed size: reads of one row or one
  bounded page through an index, never a scan of rows that grow with use, returning early
  when the record cannot match. Work that cannot be bounded goes to a job delivery. Every
  room post once scanned its room's whole history while holding one of 5 connections.
- The listener owns its reaction: Activity writes the mention notifications and Points
  records points. The emitting resource names neither.
- Inline listeners run with the emitter's actor and `authorize?`. A bookkeeping
  listener's policy admits its signal (`signal_in`), never `always()`, so the action
  cannot be called on its own.
- A listener returns nothing the emitter needs. A bulk write inside a listener passes
  `notify?: true`, and Ash sends the notices once the outer transaction commits. Do not
  return notifications from the listener.
- A job delivery (`on ..., delivery: {AshOban.Signals, queue: ...}`) stores the actor,
  so a site needs an actor persister first: a module implementing `AshOban.PersistActor`
  (`AshTemplate.Actors.Persister`), named on the delivery with `actor_persister:`.
  Pass `unique: false`: every emit carries a new `signal_id`, so the default
  uniqueness check on it finds nothing and costs every emit two queries. Job delivery
  commits with the action only when the emitter and Oban use the same Repo and the
  signal is emitted `:after_action`.
- `signal_id` is not a business key. An effect that must happen once still keys on the
  record: Points' `source_event_key` is the note or pairing id.
- Before renaming or removing a signal, one of its fields or a job-delivered listener,
  drain its queued jobs or give the listener an `upgrader`.
- A shared library emits its own signals (`RegentAgents.Signals`), and each site
  listens with a resource of its own. No library ships a listener that runs on every site.
- Pages still hear about changes through `Ash.Notifier.PubSub`; a signal does not
  replace it. A person's on-chain action is never queued, deferred or deduplicated
  through a signal (`regent-workflow`).
- Tests use `Ash.Signals.Test` (`assert_emits_signal/4`) where a rule depends on the
  signal, as `regent-workflow` ("Every change proves itself") sets out.

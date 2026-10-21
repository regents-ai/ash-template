# Standard metrics

Every site sends the same measurements under the same names, so one dashboard and
Fly Sentinel can read all six sites alike, and Fly's `app` label tells them apart.
The template's `platform/lib/ash_template_web/telemetry.ex` is the reference. A site
copies it, renames `ash_template` to its own app name, keeps the series for the
features it has, and adds its own series in the same style.

## Rules

- **Reporter.** Peep (`{:peep, "~> 5.0"}`), started by the site's `Telemetry`
  module, with `AshTemplateWeb.Metrics` serving `/metrics` on the private metrics
  port. `metrics.ex` is a shared file: `scripts/drift.sh` compares each site's copy
  with the template's.
- **Units.** Peep adds every observation to its total as a whole number. Times in a
  histogram are whole microseconds (`*_microseconds`); money is in billionths of a
  dollar (`*_nanodollars`). A gauge that holds an age is in seconds (`*_seconds`).
- **Buckets.** Every histogram uses `AshTemplateWeb.Telemetry.Buckets`, which
  counts an observation at or below its bound, with the bounds listed beside it.
- **Names.** `health_*` is the set Fly Sentinel reads from every site. `<app>_*` is
  the site's own: `ash_template_*` here, `keyfleet_*`, `regents_*` and so on in the
  sites. `vm_*` is the engine's. Counters end in `_total`.
- **Tags.** Only values from a fixed list in code or a route pattern: a queue, a
  worker, a reason, a route like `/rooms/:id`. Never a path, address, account,
  wallet, agent, request or record id.

## The standard set

Names are as Prometheus shows them. A site sends a row only when it has the
feature (chain requests, Jev, shared readings).

| Name | Type | Tags | What it measures |
| --- | --- | --- | --- |
| `<app>_request_duration_microseconds` | histogram | `route` | Time of each request the router sends to a page or controller |
| `<app>_repo_query_microseconds` | histogram | — | Whole time of each database query, the wait for a connection included |
| `health_db_queue_microseconds` | histogram | — | Wait for a database connection, per query |
| `<app>_jobs_finished_total` | counter | `queue`, `worker`, `state` | Job runs that ended done, cancelled or snoozed |
| `<app>_jobs_failed_total` | counter | `queue`, `worker`, `state` | Job runs that failed |
| `<app>_jobs_duration_microseconds` | histogram | `queue`, `worker` | Time of each job run |
| `health_job_oldest_age_seconds` | gauge | `queue` | Age of the oldest unfinished job in each running queue |
| `health_chain_request_failures_total` | counter | `method`, `class`, `chain_id`, `scope` | Chain requests that got no answer |
| `health_wallet_send_failures_total` | counter | `flow`, `reason` | Wallet presses the browser reported as not sent or not confirmed |
| `health_agent_activity_unread_total` | counter | `reason` | Agents' activity reads from the sign-in service that gave no reading |
| `health_open_pages_refused_total` | counter | — | Live pages refused because their address already held the limit open |
| `health_shared_reading_oldest_seconds` | gauge | `kind` | Seconds since the oldest shared reading of each kind was read |
| `health_shared_reading_late_keys` | gauge | `kind` | Keys read longer ago than their producer allows |
| `health_shared_reading_never_read_keys` | gauge | `kind` | Keys with no reading since the site started |
| `health_shared_reading_degraded_total` | counter | `kind` | Shared readings that could not be taken |
| `<app>_shared_reading_keys` | gauge | `kind` | Keys held |
| `<app>_shared_reading_table_bytes` | gauge | — | Memory the shared readings table holds |
| `<app>_shared_reading_refused_total` | counter | `kind`, `reason` | Readings refused |
| `<app>_shared_reading_woken_total` | counter | `kind` | Wake-ups sent to open pages |
| `<app>_privy_browser_failure_total` | counter | `reason` | Sign-in failures the browser reported |
| `<app>_privy_session_refused_total` | counter | `stage`, `reason` | Sign-ins the server refused |
| `<app>_session_bootstrap_rate_limited_total` | counter | `source` | Sign-in starts turned away by the rate limit |
| `<app>_session_authority_absent_row_total` | counter | — | Sessions reset because their sign-in record was missing |
| `<app>_jev_questions_total` | counter | `outcome` | Questions asked of Jev |
| `<app>_jev_input_tokens_total`, `<app>_jev_output_tokens_total` | counter | — | Tokens Jev was billed for |
| `<app>_jev_cost_nanodollars` | histogram | — | What OpenRouter charged per Jev question |
| `<app>_jev_duration_microseconds` | histogram | `outcome` | Time of each Jev question |
| `vm_memory_{total,processes,binary,ets,code,atom}_bytes` | gauge | — | The engine's memory |
| `vm_total_run_queue_lengths_{total,cpu}` | gauge | — | Work waiting for a scheduler |
| `vm_system_counts_{process,atom,port}_count` | gauge | — | Processes, atoms and ports alive |

A site's own series follow the same rules, for example Techtree's
`techtree_results_published_total` and `techtree_results_read_total`. How often one
address is fetched, such as an agent guide like `/skill.md`, needs no series of its
own: `<app>_request_duration_microseconds_count` has it by route.

## Fly Sentinel

Fly Sentinel's metrics contract (`docs/metrics-contract.md` in fly-sentinel) names
the `health_*` series it reads. Its database-wait tile reads
`health_db_queue_seconds`; until it reads `health_db_queue_microseconds`, that tile
shows "Waiting for data" for every site that sends the standard name.

# Figures every visitor sees alike

A crowd on one page must cost about what one visitor costs. It does when a figure
that is the same for everyone is read once and handed to every open page, and it
does not when each page rereads it on every notice. This page says which figures
may be shared, the two ways to share one, and what each open page may cost in
memory. Founder target, 13 October 2026: 1,000 to 2,000 visitors online at once
on Autolaunch, Patchbay and Keyfleet, with as many agents.

## Three kinds of thing on a page

| What the page shows | How it reaches the page |
| --- | --- |
| Anything that differs by viewer: balances, positions, drafts, what a person muted, anything a policy narrows | Reread under the viewer's scope when a notice arrives. The notice says "read again" and carries nothing (`forms-and-liveview.md`). This is the default and it does not change. |
| A public figure held in one saved row: an auction's raised total, a post's reply count | The row's own `pub_sub` publication carries the public fields. Pages apply the payload; nobody rereads. |
| A public figure no saved row carries (a chain's newest block), or one built from many rows (the latest trades across a market) | `AshTemplate.SharedReading`: one producer reads it, every page fetches the one copy. |

A figure is public only when a signed-out read answers it, with the same value
for every visitor. If a policy, a filter on the actor or a field policy could
change the answer for anyone, it is the first kind. When unsure, it is the first
kind.

## A public row: publish its public fields

```elixir
# What a signed-out visitor may see, named one by one.
def public(launch, left),
  do: %{id: launch.id, name: launch.name, raised: launch.raised, left: left, version: launch.version}

actions do
  update :record_bid do
    accept [:raised]
    change increment(:version)
  end
end

pub_sub do
  module Phoenix.PubSub
  name MySite.PubSub
  prefix "public:launch"
  broadcast_type :broadcast

  publish :record_bid, [:id],
    load: [:left],
    returns: :map,
    transform: &MySite.Launch.public(&1.data, &1.data.calculations.left)
end
```

```elixir
def mount(%{"id" => id}, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(MySite.PubSub, "public:launch:#{id}")
  launch = MySite.Launches.get_launch!(id, load: [:left], actor: nil)
  {:ok, assign(socket, launch: MySite.Launch.public(launch, launch.left))}
end

def handle_info(%{topic: "public:launch:" <> _id, payload: %{version: version} = launch}, socket)
    when version > socket.assigns.launch.version,
    do: {:noreply, assign(socket, launch: launch)}

def handle_info(%{topic: "public:launch:" <> _id}, socket), do: {:noreply, socket}
```

The rules, each with its reason:

1. **Name the fields one by one.** Never `transform & &1.data`: the whole record
   carries every attribute, including ones added later that nobody meant to
   publish. `returns` states the payload's type beside it.
2. **The topic starts with `public:`**, a prefix no per-person topic uses, so a
   reviewer can see from the topic alone that the payload is open to everyone.
3. **The payload carries an order marker the database sets**, and a page keeps the
   newer. Two saves close together can reach a page in either order. A counter
   moved by `increment/1`, or a time set by `expr(now())`, is set by the database;
   a time the server computes is not, and two servers' clocks disagree.
4. **Calculations and aggregates come from the publication's `load`**, read once
   per save. Ash (3.34) puts a loaded aggregate, attribute or relationship on the
   record and a loaded calculation in `data.calculations`, so the transform reads
   a calculation from there. On the record itself it is still `%Ash.NotLoaded{}`.
5. **A page that opens later reads the row once in `mount`, as a signed-out
   actor** (`actor: nil`), through the same function that builds the payload. If
   that read is refused, the row is not public.
6. **A policy that tightens removes the publication in the same change.** The
   publication is a second door to the row; the policy does not guard it.
7. **A notice can be lost.** Notifiers run after the commit and are sent at most
   once. A page showing a public row heals on its next navigation; a figure that
   must never be stale past a few seconds is a shared reading with a producer,
   below.

`SharedReading` is not for a single public row. A site reaching for it there is a
review finding: the row already has a save, and the save already has a
publication.

## A shared reading: `AshTemplate.SharedReading`

`platform/lib/ash_template/shared_reading.ex` is the whole of it, and
`/showcase/figures` with `AshTemplate.ChainHead` is the worked example. A site
copies the module as it stands and adds its own kinds.

```elixir
def mount(_params, _session, socket) do
  key = AshTemplate.ChainHead.key(8453)
  if connected?(socket), do: AshTemplate.SharedReading.subscribe(key)
  {:ok, assign(socket, head: AshTemplate.SharedReading.fetch(key))}
end

def handle_info({:shared_reading, key}, socket),
  do: {:noreply, assign(socket, head: AshTemplate.SharedReading.fetch(key))}
```

Subscribe first, then fetch, so a reading that lands between the two still wakes
the page. A page that stays open while what it shows changes (one live view
across many lists) calls `unsubscribe/1` for each key it stops showing.

What it holds, and what it refuses:

- **A key is `{kind, id}`**, built only by site code: `kind` from the module's
  fixed list and `id` a value the site already holds in its own rows or settings.
  Never a key, or any part of one, taken from a request.
- **A kind is a reviewed entry.** It states why a signed-out visitor may see the
  reading, the most keys it may hold and the largest reading it accepts. For a
  kind built from rows, that reason names the resource and the read a signed-out
  visitor is allowed. A
  reading over the size, a key past the count and a reading that is not small
  plain data are refused and counted; the reading held before stays.
- **A reading is small plain data**: numbers, strings, atoms, dates, `Decimal`s,
  and maps, lists or tuples of them. Never an Ash record and never a field that
  belongs to one viewer.
- **Each entry carries `at`**, when it was last read, and `degraded?`, whether the
  last attempt failed. A producer that cannot read calls `degraded/1`; the last
  reading stays on show with the mark. A first attempt that fails stores the mark
  with no reading, and pages hear it the same way.
- **One producer owns each key.** Only it calls `put/2`, `degraded/1` and
  `delete/1`, and it deletes the key when the row or setting behind it ends.
  A producer whose keys come and go asks `ids/1` on each pass what is held and
  deletes what its fresh read no longer has. It never keeps its own list, which
  a restart of the producer alone would lose while the table keeps the keys.
  Writes go through the one owner process; reads never do.
- **Pages are woken only when the reading or the mark differs** from what is held,
  never because time went by. The message is `{:shared_reading, key}` and carries
  nothing; the page fetches. A field that says when a reading was taken, not what
  it is ("as of block N"), would wake every page on every pass. The producer
  compares the new reading to the held one without those fields and, when the
  rest is the same, puts the held reading back: `at` moves and nobody wakes.
  Words every visitor sees alike that age with the clock ("last check-in 3
  minutes ago") are what the page shows, so the producer writes the words into
  the reading on its pass, and pages wake when the words change. The times
  behind them stay out of the reading, and no page redraws them on a timer.
- **A shared reading never disables or delays an on-chain button.** Stale,
  degraded or absent, every button stays live. Only the chain's own state at the
  latest block, read for that press, may block one.

Refused at design: a time-to-live, a read-on-miss inside `fetch/1`, a second
producer for a key, any value that differs by viewer, any key or value from a
request, and `:persistent_term` for a value that changes.

### Producers

A producer is a supervised process started after `AshTemplate.SharedReading` and
before the endpoint. Its first read happens inside its own start, with a bounded
wait, and stores the `degraded?` mark when it fails. So the site begins serving
with every key answered one way or the other, and a provider being down never
keeps the site from starting. Two shapes are allowed (`elixir-stack`):

- **A supervised reader of an outside clock**, such as `AshTemplate.ChainHead`.
  One that also records what it read writes its rows first and stores the
  reading after, so a page never shows a figure the database does not hold.
- **A reread on notice**, for a reading built from the site's own rows: the
  producer subscribes to the rows' notices, rereads at most once a second however
  many arrive, and holds nothing but "a reread is due". `AshTemplate.Rooms.Activity`
  is the worked example: each room's message count and newest message time, on
  `/showcase/figures`. Two things come with this shape:
  - **A lost notice is healed each minute.** The site's Oban schedule runs
    `AshTemplate.SharedReading.Heal` once a minute for each such kind (one line
    in `cron`), which asks every machine's producer of that kind to read all
    its keys again (`SharedReading.heal/1`, heard after `subscribe_heal/1`).
    The producer never schedules this itself. A schedule line naming a kind
    the module does not hold fails its job each minute into saved errors.
  - **Every kind states `within`**, the seconds inside which a working producer
    reads each key again whether or not anything changed. The minute's pass
    puts back a reading that is the same, so its `at` moves and nobody wakes: a
    quiet room keeps a young reading and never reads as a stopped producer.
    `health.shared_reading.late.keys` counts the keys older than their kind's
    `within`, so one alarm ("late above 0") serves every kind.

  A reading counted over many rows costs a pass over those rows each time. A
  count over a room of thousands is fine; past that, keep the figure on a row
  of its own and publish that row (the section above).

A producer's cost no longer grows with the pages open, but it does not stop when
nobody is looking: it is keys times passes, every pass, with no visitor on the
site. Bound it on purpose and say the bound beside the kind (Autolaunch reads at
most 100 open auctions a pass, plus up to 100 finished ones every fourth pass,
at about 29 chain requests an auction).

Measure a producer at a production provider's pace, not at a local node's. At
25 ms a request, Autolaunch's pass took longer than one two-second block; its
check that the pass's block was still the newest then failed every pass, and
the figures stayed stale for good. Nothing showed it at local speed. A chain
producer pins every read of a pass to one block by its hash and, before it
stores, asks whether that block is still part of the chain, never whether it is
still the newest.

### Measurements

`health.shared_reading.oldest.seconds` (by kind) is how long ago the oldest key
of a kind was read: a producer that has stopped shows as a number that only
grows. `health.shared_reading.late.keys` counts the keys read longer ago than
their kind's `within`. `health.shared_reading.never_read.keys` counts the keys that have had no
reading since the site started, which the age cannot show.
`health.shared_reading.degraded.total` counts failed readings by kind, and a
reader's failed requests count in `health.chain_request_failures.total` under
its own `scope`, apart from the wallet's.
`<app>.shared_reading.keys`, `.table.bytes` and `.refused.total` watch the
bounds, and `.woken.total` counts the wake-ups sent to pages, by kind.

## Quiet pages

A page does work only for what it shows. It subscribes to the topics of its own
subject and ignores a message that changes nothing on screen.

Any rule of the form "only when it concerns me" or "not again if I just
updated" has one case to trace before it is cleared: a message about a sibling
arrives, and a message about the page's own subject arrives right after it, in
the same second. The page's own reading must still land. Write that case down
and follow it through the code. A filter keyed on the subject's id is safe; one
keyed on "I handled something a moment ago" is not.

## Memory for each open page

With many pages open, memory gives out before speed does, so the budget is
counted per page.

The arithmetic: a 2 GB machine keeps half for everything that is not a page (the
runtime, the database pool, jobs, a burst). The other 1 GB across 2,000 pages is
**0.5 MB a page**. Autolaunch's live site measured 4.9 MB a page on 13 October
2026, which fills 2 GB at about 275 pages; that number, not requests a second,
was its ceiling.

An open page is two processes: the websocket connection and the page itself.
Measure both, by kind, before trimming anything. Open N pages against a local or
rehearsal server, let them settle, and read the machine's total memory
(`vm.memory.total`) before and after; the difference divided by N is one page at
rest. Then sum memory by process kind to see where it sits. Read it again after
a minute of live updates, since a page that grows with each update is a leak.

What Autolaunch's practice site showed with 50 auction pages open (its chief's
measurement, 13 October 2026), 2.94 MB a page in all:

| Part of one open page | Memory |
| --- | --- |
| Websocket connection process | 1.67 MB |
| Page process | 0.38 MB, of which all assigns together were about 14 KB |
| Binaries held outside the processes | 0.24 MB |
| A nested live view (a ticker, a search box) | about 3 KB |

So the page's own data was not where the memory was, and a guess would have
trimmed the wrong thing.

**Every site's LiveView websocket sets `fullsweep_after: 0`**, as the template's
endpoint does:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [...], fullsweep_after: 0]
```

The connection process builds the page's first payload once and then holds on to
that memory, because a process that does little is rarely swept in full. With the
setting it is swept each time. In the same trial the connection process went from
1.67 MB to 0.09 MB and a whole page from 2.94 MB to 1.43 MB, with no processor
cost that could be told from noise. It is Phoenix's own documented setting
(`Phoenix.Endpoint.socket/3`).

Not all of a page's memory sits in its processes. With 2,000 idle Patchbay forum
pages (the siwa chief's measurement, 14 October 2026), the setting took a page
from 0.44 MB to 0.37 MB, and 0.34 MB of what was left was a buffer the network
driver holds for each open connection, outside every process, which no process
setting reaches. A fixed receive size on the web server's connections did not
change it on a Mac. Measure it on the server the site really runs on before
counting it as the floor of a page.

The page process itself needs no setting: LiveView compacts a page's memory
once it has been idle for 15 seconds (`hibernate_after` under the endpoint's
`live_view` settings; the template keeps the default). A burst of wakes grows
its heap for that long and no longer. Never raise it. Measure a page at rest
more than 15 seconds after its last message, or the figure includes that heap.

What still holds for any page:

- **Assign what the page renders.** An Ash record carries its metadata and every
  loaded relationship; assign the fields as a map, or one record with nothing
  loaded. A list the page only renders goes in a stream, which the server does
  not keep.
- **The same figure on every page is held once**, in `SharedReading` or a
  publication's payload, and each page keeps only what it renders. A shared
  reading saves the reads, not the copy: a page that assigns what it fetched
  holds its own copy (Autolaunch measured 282,496 bytes a page for a
  1,000-price ladder). So a kind's byte limit is also a cost per viewer, the
  limit times the pages showing that key, and a page assigns only the part it
  draws.
- **A page that is sent a message every block never rests.** Waking a page only
  when a figure it shows has changed is what lets it sit idle between changes.

## More than one machine

Each machine keeps its own table and runs its own producers, and a wake-up reaches
that machine's pages only. A reader of an outside clock needs nothing more. A
producer that rereads on a row's notice must hear that notice on every machine,
and the minute's heal reaches the other machines the same way (unjoined, their
keys go late and `health.shared_reading.late.keys` says so),
and a public row's publication must reach every machine's pages, so a site joins
its machines into one cluster before it runs a second one. No Regent site runs a
second machine today; adding one is a release condition to check against this
section, not a setting to flip.

## Where the template stands

`AshTemplate.Rooms.Message` is the worked example of a public row, and
`AshTemplateWeb.RoomsLive` of a page that applies one:

- `Message.public/1` names the fields; the publication and the page's own read
  both go through it, so a message read and a message published are the same
  map. The topic is `public:room:<room>`. A delete carries `%{id, room}`.
- The order marker is `edited_at`, set by `expr(now())` on every edit. The page
  keeps, for each message it has shown edited, the time of that edit (or that
  it was deleted), and a notice that is not newer changes nothing. It keeps
  nothing for a message nobody edited, so the cost is a few entries a page.
- An edit can overtake its own post. The page knows when the newest message it
  shows was posted, so an edit of a later one goes at the bottom as the post
  would have, and the late post then changes nothing.
- Which messages a reader sees is the first kind of thing (their mutes), and it
  stays a filter on the page: the payload is the same for everyone, and each
  page leaves out what its reader muted.

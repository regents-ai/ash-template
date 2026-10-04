# App shell structure plan

Founder request, 2026-10-04: give the template's signed-in app the panel structure of
the two reference sketches (left rail, sidebar, tabs, main content, right side bar,
bottom bar, and the top bar's logo, search, icons and person menu). The sketches guide
the structure, not the content: every panel and menu is present in the template with
example content a real product replaces.

## Today

`AshTemplateWeb.Components.Shell` renders one header (logo, phone menu button, theme
switch, Regent links, person menu), one sidebar of four links (Overview, Notes, Rooms,
Account) that becomes a drawer on phones, and `<main id="route-content">`.
`AshTemplateWeb.ShellLive` is the one LiveView behind every app page, so moving between
pages patches the content and keeps the shell. `AshTemplateWeb.RouteCatalog` describes
each page (its sidebar, header controls and scroll rule).

## Target

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ top bar: logo · search (⌘K) · help · what's new · assistant · bell · you │
├────┬──────────────┬─────────────────────────────────────┬────────────────┤
│rail│ sidebar      │ tabs                                │ right side bar │
│    │ (this        ├─────────────────────────────────────┤ (context for   │
│    │  section's   │ main content                        │  this page)    │
│    │  lists)      │                                     │                │
│ you│              │                                     │                │
├────┴──────────────┴─────────────────────────────────────┴────────────────┤
│ bottom bar: status · background jobs running · links · version          │
└──────────────────────────────────────────────────────────────────────────┘
```

| Panel | What it holds in the template |
| --- | --- |
| Top bar | The logo (our mark). Search with ⌘K / Ctrl+K. Icons: help (opens help in the right side bar), what's new (the changelog), assistant (opens the assistant in the right side bar), notifications bell with a count. The person menu: Account, theme, Disconnect. Signed out, a Sign in button replaces the bell and the person menu. |
| Left rail | One icon per section: Home, Notes, Rooms, Chat, Settings. The person's picture at the bottom. Each icon has a visible tooltip and an accessible name. |
| Sidebar | The open section's own list. Home: workspace links and favourites. Notes: the person's notes. Rooms: the rooms with unread counts. Chat: the conversations and "New chat" (the Ash AI chat page's list lives here). Settings: the account pages. It can be collapsed to give the content more room. |
| Tabs | Views of the open section. Home: Overview, Activity. Settings: Profile, Wallets, Connections. A section with one view shows no tabs. |
| Main content | The page itself, as today. |
| Right side bar | Context for the page, collapsible. A "Get started" checklist worked out from the person's real data (signed in, wallet linked, first note, first room post, first chat), the assistant box (talks to the chat page's free stand-in), "Here now" on a room page, and one promotional card. |
| Bottom bar | A status dot (the site's own health check), the number of background jobs running right now, links (Status, Changelog, API, Help, Privacy, Terms) and the running version. |

### Phones and small screens

- The rail and sidebar fold into the existing drawer behind the menu button.
- The right side bar becomes a sheet opened from its top-bar icons.
- Tabs scroll sideways.
- The bottom bar shrinks to the status dot and version.
- Every panel keeps its landmark (`nav`, `main`, `aside`, `footer`) and keyboard order, and
  the skip link still jumps straight to the content.

## How it is built

The standard tool for each part (elixir-stack design check):

- **The frame and its panels:** `Shell` function components with one slot per panel.
  `ShellLive` stays the single LiveView, so the frame never reloads between pages.
- **What each page puts in each panel:** `RouteCatalog` gains a section per page (rail icon,
  sidebar model, tabs, right side bar parts), checked by the existing route handoff.
- **Open/closed panels:** browser state through the existing `ShellBehavior` hook and the
  site's own cookie, like the theme. Nothing is stored server-side.
- **Search:** Ash read actions on the domains (pages and actions from `RouteCatalog`; the
  person's notes and room messages through their own policies), opened as a dialog.
- **Notifications:** a `Notification` Ash resource on AshPostgres, per person, written in the
  same transaction as the thing it reports, pushed to open pages with `Phoenix.PubSub`.
- **Background jobs running:** Oban's own `:telemetry` job start/stop events, counted and
  sent to open pages with `Phoenix.PubSub`. No database polling.
- **Status dot:** the existing health check.
- **Version:** the release version and commit, read once at boot.
- **Looks:** `Regent.Primitives` and `Regent.Structure` from the design system; panel CSS in
  `assets/css/components/shell.css`.

## Phases

Each phase ends checked on desktop, phone width and keyboard, then goes live on
template.regents.sh.

1. **Frame:** top bar with the icons and person menu, left rail, section sidebars, bottom bar
   links, version and status dot. Rooms and the chat page move their lists into the sidebar.
2. **Tabs and right side bar:** section tabs, collapsible right side bar with the Get started
   checklist, "Here now" and the promotional card.
3. **Search:** the ⌘K dialog over pages, actions, notes and room messages.
4. **Live parts:** notifications and the bell, the background-jobs count, the assistant box.

## Decisions

Open; asked 2026-10-04 (numbered 6–10 in that reply).

6. Tabs fixed per section, or tabs the person opens and closes like the sketch's "New Tab".
7. Search over pages, actions, notes and room messages, or pages and actions only.
8. A real notifications example (a mention in a room, a note delivery that failed), or a
   bell with nothing behind it yet.
9. Build the frame in the template first and move it to the shared design system when a
   second site adopts it, or build it in the design system from the start.
10. A promotional card in the right side bar, or none.

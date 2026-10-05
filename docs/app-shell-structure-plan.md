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
| Sidebar | The open section's own list. Home: shortcuts (write a note, start a chat, the General room, connect an account). Notes: the person's notes. Rooms: the rooms. Chat: the conversations and "New chat" (the Ash AI chat page's list lives here). Settings: help links (the account pages are its tabs). It can be hidden to give the content more room, and stays hidden until shown again. |
| Tabs | Views of the open section. Home: Overview, Activity. Settings: Profile, Wallets, Connections. A section with one view shows no tabs. |
| Main content | The page itself, as today. |
| Right side bar | Context for the page. Closed until the person opens it, and remembered open or closed; a light on its top-bar icon pulses while it holds something new the person has not opened it to see. It holds one promotional card, a "Get started" checklist worked out from the person's real data (signed in, wallet linked, first note, first room post, first chat), the page's own part ("Here now" and muted people on a room page), the assistant box (talks to the chat page's free stand-in) and help links. |
| Bottom bar | A status dot (the site's own health check), the number of background jobs running right now, links (Help, API, What's new, For agents, Privacy, Terms) and the running version with its commit. |

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
- **Open/closed panels:** browser state on `<html data-aside data-sidebar>`, set by
  `assets/js/shell_panels.ts` and kept in the cookies `ash_template_aside` and
  `ash_template_sidebar`, which `AshTemplateWeb.Plugs.Panels` reads so the first paint is
  right. LiveView never patches them. Nothing is stored server-side. The pulsing light
  compares a digest of the side bar's content (`data-aside-digest`) with the last one seen
  in this browser.
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

Settled by the founder on 2026-10-04.

1. Tabs are fixed per section (6 a).
2. Search covers pages, actions, notes and room messages (7 a).
3. The bell has a real example behind it: a mention in a room (8 a). A mention is `@` and
   a name someone has posted under in that room; it reaches no one who muted the author.
4. The frame is built in the template first and moves to the shared design system when a
   second site adopts it (9 a).
5. The right side bar is collapsible, closed by default, and a pulsing light shows when it
   has something new (founder's own answer to 10).
6. The promotional card shows whenever the right side bar is open.

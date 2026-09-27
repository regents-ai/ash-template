---
name: regent-notion
description: Regent's public Notion data room and the Planning, Spec and Implementation pages each product keeps there. Use whenever a Regent thread adds an idea or open decision, drafts or ticks a done-criterion, records proof that work merged, or edits any Regents Labs Notion page.
---

# Regent Notion: the data room and project pages

Regent builds in public. The whole Notion teamspace, home page "Regents Labs", is the
public data room: investors, partners and the public can read it. Many agent threads
write to it at once, so follow these rules exactly.

## Layout

```
Regents Labs (home)                    29459985-6802-805f-ba39-ff82f2d2c833
├── Data Room                          3e359985-6802-8171-9c17-ebe5ad04400f
│   ├── company pages (one-pager, why now, traction, roadmap, how we build,
│   │   token vesting, revenue to stakers, holders, tech, contracts and
│   │   security, company and legal, raise)
│   ├── Autolaunch                     3e359985-6802-8180-aec4-f17ea5edb9c3
│   ├── Techtree                       3e359985-6802-81a0-9897-f1e4c2086b32
│   ├── Patchbay                       3e359985-6802-81f5-a7e5-fc63422095ba
│   └── KeyFleet                       3e359985-6802-8152-9c18-d39feb238869
│       ├── Planning                   3e459985-6802-8172-afc3-d10669e79f22
│       ├── Spec                       3e459985-6802-8190-a87f-fdff64df34be
│       └── Implementation             3e459985-6802-8166-ba1f-e7b84aee3e40
├── Go-to-market                       3e359985-6802-81c4-8679-c7ebe90af362
├── Operations                         3e359985-6802-8178-b371-f58daceac67e
└── Archive (old pages, reference only) 3e359985-6802-815c-8fe9-dbecfc23919b
```

IDs were recorded on 2026-09-22 and 2026-09-24. Fetch a page before relying on its ID.
If one has moved, search for it by title, and update this list.

- **Product pages** are short "mini-homes": what the product is, a screenshot and
  links. Each product page has three child pages: Planning, Spec and Implementation.
  KeyFleet has them already. Other products get them when their lane first needs them.
  Create all three at once, as children of that product's page and with these exact
  titles, then add their IDs above.
- **Company pages** in the Data Room hold Sean's content. Yellow callouts mark blanks
  that Sean fills in. Don't edit company pages unless the founder asks.
- **Archive** is history. Never cite it as current, and never move content out of it
  without asking.

## Planning: any agent's scratchpad

- Any thread may add ideas, open questions, TODOs and founder decisions.
- Start each entry with the date (from `date -u`) and your lane, for example
  "2026-09-24 · keyfleet-treasury".
- **Open decisions** state the question, the options and a recommendation. When Sean
  decides, record it as "Decided <date>: <choice>". Then move it into Spec as a new or
  changed item, and remove it from Planning.
- **Keep it bounded:** at most 15 open items.
  - You may remove your own entries at any time.
  - You may remove another thread's entry only when it has been decided, moved to
    Spec, or left untouched for 14 days.
- **Changing a locked Spec item:** propose it here as "Spec change: S3 …".

## Spec: the definition of done

- **Numbering:** items are S1, S2, … and a number is never reused.
- **Content:** each item has a one-line goal and a checklist of what must be true.
  Write it as observable results a person could check, not as implementation steps.
- **Status line:** every item carries one.
  - "Draft": agents may draft and edit it.
  - "Locked by Sean, <date>": only Sean locks an item, and only when he says so. Only
    Sean unlocks it. Agents never change a locked item's wording.
- **Progress:** an item with some lines done may say "Built so far". An item waiting on
  something may say "On hold: <reason>".
- **Ticking a line:** only when Implementation cites proof for it. If proof is
  removed, untick the line.

## Implementation: the proof, built up over time

The agent completing the work writes here, under a heading per Spec item (S1, S2, …).

- **For each piece of work,** cite:
  - the commit hash and title;
  - the files changed;
  - the checks actually run and their results;
  - screenshots for anything a person sees.
- **Main branch only.** Cite only commits on the product repository's main branch.
  Before ticking a Spec line, and whenever you edit this page, check every commit it
  cites with `git merge-base --is-ancestor <hash> main`. Remove any proof that fails.
- **Refactors.** If a refactor deletes or replaces cited work, even for a moment, remove
  that proof and untick its Spec lines. Cite the new commit once it is merged.
- **Links.** Link each commit to its GitHub page once it is pushed. Until then, mark it
  "not yet public".
- **Screenshots.** Upload them into the page with `notion-create-file-upload`, then
  embed the upload. Never cite a local file path. Only screenshots of the merged
  version count.
- **Gaps.** Say what was not checked (for example "real-phone check not done"), not
  only what passed.

## Everything is public

- **Never write:** secret values or their names, private keys, RPC URLs, `.env`
  contents, private user data, wallet addresses of private people, private chat links,
  or anything a founder decision kept private.
- **Only if Sean has said the item may be public:** partners or other companies,
  money, pricing, revenue, fundraising or token allocations.
- **Tone:** write in plain English. Readers are investors and the public, not engineers.

## Working with the Notion connector

- **Auth drops.** The connector loses its authorization often. If Notion tools are
  missing or ask for authentication, tell Sean to re-authorize Notion in his claude.ai
  connector settings. Carry on with the code work and note which Notion updates are
  owed. Never ask for tokens or codes.
- **Read before writing.** Fetch the page first. Other threads edit the same pages, so
  change only your own section with targeted edits. Never rewrite a whole page.
- **Order.** Moving pages appends them to the end of the parent, and child-page
  blocks can't be reordered in place. To reorder, move pages aside and back one by
  one, or move headings around them instead.
- **No delete tool.** To retire a page, move it to Archive or tell Sean to trash it.
- **After a merge or decision,** update Notion in the same session: Planning → Spec,
  proof into Implementation, then tick Spec.

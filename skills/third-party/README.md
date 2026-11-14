# Third-party Skills

These Skills are other people's work, not Regent's. Each folder is an exact,
unmodified copy of its author's Skill at the commit named below, and each stays under
its author's own licence, kept word for word in [LICENSES/](LICENSES/). They are here
so that anyone who clones this template, or a site made from it, has them for local
work: read a Skill's `SKILL.md`, or link its folder into your agent's Skills folder.

The web app does not serve or list them: its build skills are the template's own,
named in `AshTemplateWeb.AgentSkills`.

Never edit a file here. To take a newer version, replace the whole folder with the
author's folder at a newer commit and update its row.

## Carried

| Skill | Author | Source | Folder | Commit | Licence |
| --- | --- | --- | --- | --- | --- |
| [emil-design-eng](emil-design-eng/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/emil-design-eng` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [animate](animate/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/animate` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [review-animations](review-animations/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/review-animations` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [improve-animations](improve-animations/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/improve-animations` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [choreograph](choreograph/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/choreograph` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [gestures](gestures/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/gestures` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [animation-performance](animation-performance/SKILL.md) | Emil Kowalski | https://github.com/emilkowalski/skills | `skills/animation-performance` | `0f2e23b32bb1265e84cff8d3e75785fec953fb1b` | [MIT](LICENSES/emilkowalski-skills.txt) |
| [better-interface](better-interface/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-interface` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [better-accessibility](better-accessibility/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-accessibility` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [better-colors](better-colors/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-colors` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [better-layout](better-layout/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-layout` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [better-typography](better-typography/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-typography` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [better-ui](better-ui/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-ui` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [better-writing](better-writing/SKILL.md) | Jakub Krehel | https://github.com/jakubkrehel/skills | `skills/better-writing` | `a72290d140249813898ba8648becf6415abcb059` | [MIT](LICENSES/jakubkrehel-skills.txt) |
| [diagnosing-bugs](diagnosing-bugs/SKILL.md) | Matt Pocock | https://github.com/mattpocock/skills | `skills/engineering/diagnosing-bugs` | `5863806dd4e15c63174bee4e7515a4256792ecfa` | [MIT](LICENSES/mattpocock-skills.txt) |
| [resolving-merge-conflicts](resolving-merge-conflicts/SKILL.md) | Matt Pocock | https://github.com/mattpocock/skills | `skills/engineering/resolving-merge-conflicts` | `153fc1b93de6584562765cdce299324e1ff9e661` | [MIT](LICENSES/mattpocock-skills.txt) |
| [oban-thinking](oban-thinking/SKILL.md) | George Guimarães | https://github.com/georgeguimaraes/claude-code-elixir | `plugins/elixir/skills/oban-thinking` | `36ce0002f65b41d8c040a578c394049b1e7fea14` | [Apache-2.0](LICENSES/georgeguimaraes-claude-code-elixir.txt) |

## Notes

- `resolving-merge-conflicts` was removed from its repository on 24 September 2026
  (`daa01d8aa68ad5c61b68970ec2018d0ce9567be6`). This copy is from the commit before, so
  it gets no further fixes from its author.
- `oban-thinking` was renamed `oban` on 6 September 2026
  (`5e572b1a6e6df28a1dd5af292557d37387a892ba`, now at `plugins/elixir-dev/skills/oban`).
  This copy keeps the old name from the commit before; the renamed Skill's guidance is
  the same apart from its name, title, description and opening line.
- `diagnosing-bugs/scripts/hitl-loop.template.sh` is a template the Skill tells an
  agent to copy and edit when a person has to click through a reproduction. Nothing
  runs by itself.
- `review-animations` sets `disable-model-invocation: true`, so an agent uses it only
  when a person asks for it by name.
- Some of these Skills name Skills that are not carried: `animate` and `gestures` point
  to `../pick-ui-library/SKILL.md`, `animate` and `animation-performance` to
  `animate-expo`, `animate` and `choreograph` to `find-animation-opportunities`,
  `choreograph` to `remove-animations` (all in emilkowalski/skills), and
  `better-interface` to `interface-review` (in jakubkrehel/skills). Those names do not
  resolve here; get the Skill from its repository when you need it.

## Precedence

`AGENTS.md` and the template's own Skills win wherever these differ. The cases to
watch:

- Wallet and on-chain buttons follow [onchain-buttons](../onchain-buttons/SKILL.md):
  every press reaches the wallet. The "Submit behavior" section of
  `better-accessibility/forms.md` marks a pending button `aria-disabled="true"` and
  ignores repeat clicks; never do that to a wallet button.
- These Skills write their examples in React, Motion and Tailwind. A Regent site builds
  motion with the shared motion kit and [animejs](../animejs/SKILL.md), and pages with
  [ash-frontend](../ash-frontend/SKILL.md).
- Background jobs follow [elixir-stack](../elixir-stack/references/oban.md): for
  example, a job is unique by its state (`period: :infinity`), not by the time window
  `oban-thinking` shows.
- Visual design keeps the founder's explicit choices
  ([design system](../regent-workflow/references/design-system.md)).

## Recommended

Worth installing yourself where they help; not carried here.

| Skill | Source | Use | Not carried |
| --- | --- | --- | --- |
| design-taste-frontend | [Leonxlnx/taste-skill](https://github.com/Leonxlnx/taste-skill) (MIT) | Art direction and a look-and-fix loop for public pages | Too large to carry |
| solidity-security | [wshobson/agents](https://github.com/wshobson/agents) (MIT) | Security patterns for writing and auditing Solidity contracts | Only sites with contracts need it; the template's `contracts/` is empty |
| elixir-writing-docs, elixir-docs-review | [existential-birds/beagle](https://github.com/existential-birds/beagle) (Apache-2.0) | Writing and reviewing `@moduledoc`, `@doc`, typespecs and doctests | Needed only when writing or reviewing module docs |
| privy | [docs.privy.io](https://docs.privy.io) | Privy's own guidance on wallets and sign-in | No licence stated |
| rich-terminal-output | [autumnsgrove/lattice](https://github.com/autumnsgrove/lattice) | Tables, progress bars and panels for Python command-line output | No clear licence |
| phx plugin | [oliver-kriska/claude-elixir-phoenix](https://github.com/oliver-kriska/claude-elixir-phoenix) (MIT) | Elixir and Phoenix review agents and commands | Installed as a plugin, not a Skill folder; its `ash-framework` and `oban` Skills overlap the template's `ash-*` and `elixir-stack` Skills, which win |
| sentry-elixir-sdk | [getsentry/sentry-for-ai](https://github.com/getsentry/sentry-for-ai) (MIT) | Setting up Sentry in an Elixir app | The template does not use Sentry: `platform/mix.exs` has no `sentry` dependency |

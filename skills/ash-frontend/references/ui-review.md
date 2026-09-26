# Product-quality UI review

These are design choices for this pack, not promises made by Phoenix or Ash.

**Hierarchy:** Can someone name the page's purpose and primary action within a glance?
Use meaningful headings, restrained typography, aligned edges, and consistent spacing.
Do not label everything a platform, ecosystem, engine, or workflow. Explain the result
of an action in normal language.

**Density:** Remove repeated headings, duplicate explanations, gratuitous badges,
unused controls, and excessive nested cards. Use a real table for comparative data,
a list for a simple sequence, and a form for an edit. Keep long technical identifiers
copyable and readable without forcing the entire page to overflow.

**Controls:** Links navigate; buttons act. Every input needs a label, sensible input
type, and an error association. Preserve user input on failure. A destructive action
needs proportionate confirmation and a safe failure state, not repeated confirmations
for harmless edits. Keep primary controls usable on a phone.

**States:** An empty account is different from a filter returning no matches, a server
error, or missing permission. Explain each with one useful next action. Loading states
should not shift the whole layout. A job accepted is not a job completed. Show actual
status rather than reassuring animation.

**Accessibility:** Check keyboard order, visible focus, focus restoration for dialogs,
accessible names, readable contrast, status announcements where appropriate, and error
text beyond color. Respect reduced motion. Essential information should not require
hover. Custom browser-only effects should fail without hiding the page's content;
do not promise a LiveView-only mutation works without JavaScript unless a fallback
HTTP form was actually implemented and tested.

**Consistency:** Follow existing tokens, light/dark treatment, icon system, component
primitives, and content width. Do not add a UI library or change Tailwind versions for
a local polish task. Prefer one memorable, restrained visual idea over generic
AI-generated dashboard decoration.

**Browser proof:** Inspect the changed route at a narrow mobile width and a normal
desktop width, with long text and realistic records. Test the actual primary action,
error handling, and keyboard navigation. Screenshots document appearance; they do not
by themselves prove interaction or server authorization.

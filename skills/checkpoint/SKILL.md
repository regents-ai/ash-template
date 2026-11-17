---
name: checkpoint
description: Write a HANDOFF.md so another session can pick up a long Regent task. Use before context is cleared, when handing work to another session, or when asked for a checkpoint or handoff.
---

Write or update `HANDOFF.md` in the owning repository only when a handoff is needed.
Include the objective, branch/worktree, changed files, checks and outcomes, remaining
steps, session references and founder decisions. Preserve unrelated handoff content.
Do not include secrets. Tell the user its path and ask the next session to read it.
Saving a handoff does not require an automatic restore hook, commit, pull or push.
Saving one is not a reason to stop: after writing it, continue the task unless the
founder asked for a hand-over or the context is about to be cleared.

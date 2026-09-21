# Overnight Sequence Test — Task B

This is task B of the sequential overnight orchestration test.

Before this task began, we verified that the task-A file `docs/overnight-sequence-a.md`
was already present in the base commit `102762f4df8d2d4c9d9c72ffb1e1c677a25efbcd`
(via `git show <base>:docs/overnight-sequence-a.md`), confirming the dependent-task
prerequisite.

This re-run exercises the dependent-task step of the orchestration pipeline: a task
that depends on output produced by an earlier task in the same sequence, verifying the
dependency is established, committed, and observable before the dependent work starts.

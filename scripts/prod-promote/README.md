# Production-promote scripts (MANUAL — never an automatic hook)

Run these BY HAND, only as part of promoting to a production app — the final
steps of the promote runbook:

  backup → drift-check → apex import -id <PROD_ID> -workspace <ws>
  → @scripts/prod-promote/10-enable-automations.sql
  → @scripts/prod-promote/20-enable-rest-sync.sql
  → verify one automation actually fires

Why they exist: **every APEX import disables all scheduled jobs** —
automations and REST source sync come out of any import disabled, even when
the source carries active flags (activation is runtime state the import does
not honor).

Why they are NOT wired into push as an automatic hook (they briefly were —
design flaw, reverted): an auto-hook doesn't restore state, it ASSERTS it.
A deliberately paused job (maintenance, a misbehaving feed) would be silently
re-enabled by the next routine push. Development pushes don't need automations
running at all; production activation is a decision made at promote time, by
a human, from the curated lists below.

Keep the target lists in these scripts synced with which jobs SHOULD be live
in production — they are the authoritative statement of that intent. The
drift warning fires when a listed job no longer exists.

Verify state: `apex_appl_automations`, `apex_appl_web_src_modules.sync_is_active`.

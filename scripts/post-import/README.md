# Post-import scripts

Any `.sql` file in this directory is run automatically by `push.sh` /
`push.ps1` after a SUCCESSFUL import, via the same connection, in filename
order. They exist because of a hard-learned fact:

> **Every APEX import disables all scheduled jobs.** Automations and REST
> source sync jobs come out of ANY import disabled, even when the source
> carries `scheduleStatus: active` / `jobIsActive: true` — activation is
> runtime state the import does not honor. Without a re-enable step, every
> push silently stops your price feeds, syncs, and notifications.

Shipped samples (stamped by init; edit the target lists to match which jobs
should be live in this app):

- `10-enable-automations.sql`
- `20-enable-rest-sync.sql`

If this app has no automations or REST sync jobs, delete the samples — an
empty directory means the hook does nothing. After any push, verify one
automation actually fires. Check state via `apex_appl_automations` and
`apex_appl_web_src_modules.sync_is_active`.

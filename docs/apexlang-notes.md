# APEXlang field notes — things the docs and skills don't tell you

Hard-won specifics from real apps. **The authoritative source is always an
existing validated page in this app** — when in doubt, find one that does what
you want and copy its shape. Append to this file every time validation or the
Builder teaches you something; this is the project's institutional memory.

## Page structure

- Modal/drawer pages put regions in `contentBody`, **not** `body`.
- `addRowIfEmpty` is only valid together with `add`.
- `width` is not a valid property on switch, select, or displayOnly items.

## Interactive Grids

- An IG **must have a `savedReport`**, and rows are invisible until it lists
  `displayColumns` — freeze and width settings live there too, not on the
  column definitions.

## Layout

- `startNewRow: false` alone puts items side by side; `newColumn: false`
  stacks them.

## Items and binds

- Date-picker binds are **strings**: give the item a `formatMask` and wrap the
  bind in `to_date(:PNN_X, '<same mask>')` in SQL.
- String binds inside `union all` branches need explicit `to_number()` or the
  branches disagree on type.
- Filter items (any page): a Change DA plus
  `warnOnUnsavedChanges: ignore`, or navigation nags about unsaved changes.

## Reports

- Classic-report columns rendering HTML need
  `security { escapeSpecialChars: false }`.
- Hidden columns take no `heading`.

## Dialogs / drawers

- Parent pages refresh on **both** `apexafterclosedialog` and
  `apexafterclosecanceldialog` — handle both or cancel paths go stale.

## Export shapes

- A page with no alias exports as bare `pNNNNN.apx`, not `pNNNNN-<slug>.apx` —
  anything globbing page files must accept both.

## Encoding

- **Non-ASCII literals in `.apx` embedded SQL are an encoding hazard** — the
  round-trip crosses several SQLcl I/O boundaries that don't all agree on
  charset, and a mangled literal passes validation and corrupts silently at
  runtime. Build special characters with `chr()` codepoints (AL32UTF8)
  instead: `chr(176)` for °, `chr(8212)` for —, `unistr('\00e9')` for é.
  Keeps the file pure ASCII, which no boundary can damage.

## Running `apex validate`

- Full validation runtime scales with **page count** — a large app takes tens
  of minutes. Run it in the background and capture **full output**: errors
  print before the final summary, and piping through `tail` silently hides
  earlier errors.
- **Page-level validation takes seconds** (`apex-validate.sh -pages pNNNNN …`):
  a staged copy with shared components + only the pages under test. Caveat:
  cross-page reference problems are invisible in a partial run — always finish
  with one full validation before push (the stamp/cache enforces this: partial
  runs never write it).
- **Exit code is 0 even when validation fails** — grep the output for
  `Validation successful`; never trust the exit code. (The shipped scripts do
  this; anything hand-rolled must too.)
- Warnings (`PROPERTY_DEPRECATED`, `INVALID_LOV` on slots) do not block a
  push; only errors do. On an old app, treat the warning list as a curated
  to-do list: drive it down to only *intentional* keeps, then document them.
- A fresh export of a long-lived app may carry **Builder-side errors**
  (duplicate button names, orphan items) — validate immediately after the
  baseline (RUNBOOK §2.4); the push gate is closed until they're fixed.

## Error patterns and fixes

- **Dangling numeric IDs** (`REFERENCE_NOT_FOUND`, or a raw ID where an `@ref`
  belongs, e.g. `authorizationScheme: 99317…`, `requiredLabel: 25363…`):
  caused by deleting a shared component (auth scheme, template, theme) in
  Builder while something still referenced it. Builder tolerates it; APEXlang
  doesn't. Re-point to a valid `@ref` or remove the block — removing an
  `authorizationScheme` is a **security decision, ask the human**.
- **`DUPLICATED_COMPONENT` on `identification.buttonName`**: two buttons on
  one page sharing a buttonName fail even in different regions. Rename one
  (buttonName is not the static ID, so renaming is safe).
- **`MISSING_REQUIRED_PROPERTY` on a saved-report `sort ( … )` block** with no
  `column:` — Builder artifact; delete the block.
- **`LOV_NOT_FOUND` on legacy enum values** — the error lists the valid
  values; map to the modern equivalent. Seen so far:
  - AOP plugin `special: repeat_header` → `irIgRepeatHeaderOnEveryPage`
  - popup LOV column `displayAs: NOT_ENTERABLE` → `inlinePopup` /
    `modalDialog` (check "not enterable" behavior in Builder afterwards)
- **Deprecated properties can travel in pairs**: removing `requestSourceType`
  alone turns its partner `requestSource` into an INVALID_PROPERTY **error**.
  Remove or keep such pairs together.

## Cleaning up deprecation warnings

Rule one: **deprecated ≠ dead.** Sort every warning into "safe to delete",
"needs migration to the modern equivalent", or "intentional keep" before
touching anything, and validate page-by-page as you go.

Slots (fix by reading each warning's own "Valid values" list — never a
blanket rename):

- `body-3` → `body` on normal pages, `contentBody` on modal-dialog pages,
  `wizardBody` on wizard pages. Same for `REGION_POSITION_03`.
- Legacy uppercase button slots (`CREATE`/`DELETE`/`CHANGE`/`CLOSE`/`EDIT`)
  → `bottom` (verify each warning's valid list includes it; button placement
  may shift slightly — eyeball after push).
- **A deprecated slot can be better than any "valid" one**: items on
  `regionBody`/`subRegions` may sit in regions whose template offers no
  equivalent slot (valid list = `afterHeader`/`beforeFooter` only). Leave the
  deprecated slot; the real fix is changing the region template in Builder.
- `legacyOrphanComponents` slot = component orphaned by an old tabular-form
  conversion; usually dead (`serverSideCondition: never`) — delete it.

Properties safe to delete (no-ops in modern APEX):

- `saveStateBeforeBranching` (state is always saved now)
- `acceptPre202UrlChecksums: false` (the modern default)
- A login button's `requestSourceType`/`requestSource` pair **if verified
  vestigial**: no process has a REQUEST-based `serverSideCondition` and no JS
  submits that request value (REQUEST then defaults to the buttonName).
  Smoke-test login after the push regardless.

Properties that still change runtime behavior — migrate deliberately or keep:

- `postCalculationComputation` — still computes. Read what it computes
  before deciding: a formatter of literals can fold into the item's source;
  but an `upper()`/`initcap()` on an LOV-backed item may be bridging a case
  mismatch between stored data and LOV return values — check the data AND
  table triggers (a before-row trigger re-casing the column means the
  property is load-bearing; keep it and document why).
- `hidePageItemsOnSameLine`/`showAllOnSameLine` — still widen hide/show
  dynamic actions, but only when another item shares the affected item's grid
  row. No `startNewRow: false` on the page → the flag is a no-op, delete it.
  If a same-line neighbor exists, add it explicitly to the action's
  `affectedElements`, then delete the flag (identical behavior, warning gone).
- `escapeBodySubstitutions: false` on Send E-Mail — deprecated AND a mild
  HTML-injection vector. If no substitution deliberately carries HTML, delete
  the block; a substitution that must stay raw gets `!RAW` (`&P1_BODY!RAW.`).
- `regionImage` — still renders the icon.

Data corruption:

- `templateOptions: ["[object Object]" …]` = corrupted value from Builder →
  replace with `#DEFAULT#` (and fix at the source eventually).

## Import-only failures (validate-clean, import-fatal)

- A saved-report `displayColumn` with **no column reference** (anonymous
  block, no `column:` — Builder corruption, same family as the column-less
  `sort`) passes `apex validate` (metadata marks `column` optional) but the
  import's generated `create_ig_rpt_column_apexlang` call lacks `p_column_id`
  and dies with PLS-00306 "wrong number or types of arguments".
  Deterministic, same line every run, `File:` blank in the error. Hunt: scan
  for anonymous displayColumn blocks lacking `column:` (named blocks carry
  the column in the name). Not a SQLcl-version issue.
- Debugging aid: the emitter's property→API mapping lives in SQLcl at
  `lib/ext/apexlang-compiler.jar` → `apexlang.zip` →
  `apexlangmeta/apexlang_meta_data.json` (componentTypes → api.expression /
  properties → apiParameter). Grep it to see which property feeds which
  PL/SQL parameter.
- **An import killed mid-run (e.g. ORA-17008) can leave the app PARTIALLY
  replaced** — some observations true, others stale. Re-run a full import to
  heal; trust nothing observed in between.

## Push-path lessons

- On a schema granted to **multiple workspaces**, `apex import` without
  `-workspace` aborts ("Multiple workspaces available…") — and `whenever
  sqlerror` does not catch it (`apex` is a SQLcl command, not SQL). Gate any
  "Imported." message on `Import successful` in the actual output. A tool
  that reports success it didn't verify is worse than one that crashes: it
  manufactures false evidence.
- **Every successful import disables the app's scheduled jobs** (see the
  promotion section below for the full mechanics). Re-enabling is a MANUAL,
  promote-only step (`scripts/prod-promote/*.sql`) — never an automatic
  push hook: an auto-hook asserts state rather than restoring it, silently
  re-enabling deliberately paused jobs on routine pushes, and dev pushes
  don't need automations running at all.
- "Push succeeded but nothing changed" is almost always a failed or
  interrupted import, **not** upsert semantics — an application import
  replaces the whole app, deletions included (field-confirmed). Check the
  app's Last Updated timestamp in Builder before theorizing.
- Long imports hold a near-idle TCP connection through a long server-side
  compile; NAT gateways / firewalls kill it (`ORA-17008`). Fix: keepalive —
  `?ENABLE=BROKEN` on the EZConnect string (verify it survives `connmgr
  show`) plus OS tuning (`net.ipv4.tcp_keepalive_time=60`, `intvl=30`); the
  flag without the sysctl does nothing (OS default probes every 2 hours).
- **Never import into a working copy** — documented to disassociate it from
  its base app, and imports into copies misbehave. Push targets main
  applications only; a copy may be exported *from*, never imported *into*.
  (Exporting FROM a copy and importing over MAIN is legitimate — see
  "Promoting a working copy to production by replace" below for the checks
  that make it safe.)
- Deletions never travel through working-copy operations (not merge, not
  refresh) — pages deleted in a copy must be deleted again in Main, and vice
  versa. Bulk tool: Utilities → Cross Page Utilities → Delete Multiple Pages.
- Pulling template scripts into an existing project needs **all** init
  placeholders stamped (`__APP__`, `__CONN__`, `__WORKSPACE__`,
  `__SCHEMA__`): `grep -n "__" scripts/*.sh` after pulling.

## Promoting a working copy to production by replace (not merge)

When a WC has diverged too far for component-level merge (mass deletions,
shared-component removals), replacing the main app via
`apex import -input <src> -id <MAIN_ID> -name "<main name>" [-alias <main alias>]`
works — but only after these checks, learned the hard way:

- **Every import disables all scheduled jobs — re-enable is a mandatory
  post-step.** Automations and REST source sync jobs come out of ANY import
  disabled, even when the source carries `scheduleStatus: active` /
  `jobIsActive: true` (activation is runtime state the import does not
  honor; WC exports additionally strip it from the files). Carrying the
  flags in source keeps the repo honest but does NOT survive the import.
  After importing over PRODUCTION, bulk re-enable via
  `apex_automation.enable` and `apex_rest_source_sync.enable` inside an
  `apex_session.create_session` context — `scripts/prod-promote/*.sql`,
  run MANUALLY as part of the promote runbook (never an auto-hook); keep
  its target lists synced with which jobs should be live. Then
  verify one automation actually fires. Dictionary checks:
  `apex_appl_automations`, `apex_appl_web_src_modules.sync_is_active`.
- **Drift-check against main first** — mandatory with multiple developers.
  Export main as APEXlang (`-skipExportDate`) and diff against the repo's
  pre-edit baseline commit. Classify each difference: own WC work (expected),
  environment state (activation flags, above), line-ending noise
  (plugin/theme static files), or a **teammate's change to main** — fold
  those into the repo before replacing, or they're destroyed.
- **Override identity on import**: without `-name` (and `-alias` if main has
  one), production takes the WC's name/alias and `f?p=ALIAS:` links break.
- **Main may carry `supporting-objects/` the WC export lacks** — inspect
  before assuming the replace preserves them.
- Keep the drift-check export as the rollback artifact; take a classic
  export too for belt-and-braces.
- Coordinate: no teammate should have a working copy in flight across the
  replace — theirs descends from the old main.
- Afterwards: delete the promoted WC, cut a fresh one from the new main, and
  retarget the repo (the new WC gets a NEW app id: `deployments/*.json`,
  script app ids, directory name).

## SQLcl / environment

- Piping commands into `sql /nolog` interactively can hang past a foreground
  timeout; prefer `sql -S /nolog` with a heredoc ending in `exit`, as a
  background task. A timed-out foreground run can leave an orphaned java
  process — check `ps` after killing one.
- Saved connection names are **global to the OS user**, shared across every
  project on the machine — see RUNBOOK §2.5 for the per-project naming rule.
  They are also **case-sensitive**: `sql -name portal_CLAUDE_RO` will not
  find a connection saved as `PORTAL_CLAUDE_RO`. Save with EXACTLY the
  casing the stamped scripts use — `grep CONN scripts/*.sh` is the
  authority. `connmgr list` / `connmgr show <name>` audits what exists.
- The `apex_*` dictionary views are **workspace-security-filtered**: the
  read-only account sees them empty unless its schema is associated with the
  workspace — "count pages in the live app" is not a check the RO door can
  perform.
- `project export` (SQLcl Projects) exports every APEX app in the workspace
  unless filtered — `export_type not in ('APEX_APPLICATIONS','APEX'),` in
  `.dbtools/filters/ddl.filters`; and `project init` appends boilerplate to
  README.md (strip it).
- Terminal discipline: paste one command at a time, never including the
  prompt (`$`, `>`, `SQL>`); hand long connect strings to `sql` as a bash
  argument — line wrap at the SQL prompt inserts real newlines into strings.

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
- **`serverSideCondition { item: … }` takes a BARE item name**, never a
  bind. `item: :P51_ID` validates clean and then never matches, so the
  component silently never renders: no error at validate time or run time.
  Only the `sqlQuery` / `plsqlExpression` forms take `:PNN_X`. After any
  bulk edit: `grep -rn 'item: :' apex/`.
- **A `source { type: sqlQuerySingleValue }` item is evaluated once per
  session** unless it says `used: always`. Without it the first value is
  cached in session state, and every later render (a branch back, a reload
  with the session in the URL) shows it again. Invisible for values that
  never change; a counter stays at "0 of 3" forever.
- **Never build a public link with session `0`** (`f?p=APP:PAGE:0::::`).
  Session 0 starts a new session, which overwrites the app cookie, so a
  signed-in user who opens the link to check it is logged out. Leave the
  session empty (`f?p=APP:PAGE:::::ITEM:val`): a live session is reused and
  an anonymous visitor gets a fresh one.
- A function with side effects (a counter, an audit insert) must be called
  from exactly one place per page view. Item source + computation + submit
  process each calling it counts three times.
- Upper-case data entry: `settings { textCase: upper }` on a `textField`
  (Builder "Text Case: Upper"). Textareas have no such setting. Hand-built
  inputs (`apex_item.text`) need the `u-textUpper` class for display plus
  `upper()` in the save process.

## Reports

- Classic-report columns rendering HTML need
  `security { escapeSpecialChars: false }`.
- Hidden columns take no `heading`.
- **Classic and interactive report column links substitute `#COLUMN#`**,
  not `&COLUMN.`: there `&ID.` resolves as a page item and comes out empty.
  Inside `target: { items: { … } }` write the escaped `\#ID#\`. A link's
  `linkText` is plain text: `linkText: #TITLE#` (`&TITLE.` renders empty;
  `\#TITLE#\` prints the backslashes). `&ID.` is right in cards regions and
  Interactive Grids.
- **A report region cannot hold a CLOB** (`ORA-00932 … got CLOB`), and
  `APEX_MARKDOWN.TO_HTML` returns one. Render long HTML in a
  `type: plSqlDynamicContent` region with
  `htp.prn(dbms_lob.substr(l_html, 8000, l_pos))` in a loop.
- **An Interactive Report's displayed column order lives in the saved
  report** (`savedReport … ( displayColumn X ( sequence: N ) )`), not in the
  column's `layout { sequence }`. Editing only the column definitions
  reorders the Builder's list, imports cleanly and changes nothing on the
  page. Edit both so they agree. Users with their own saved report keep
  their order until they reset it from the Actions menu.
- A classic report on the `@/cards` template prints its placeholders
  literally (`#CARD_SUBTITLE#`) unless every template attribute is mapped,
  and that mapping is not expressible in APEXlang. Use a native `cards`
  region: `title { column }`, `subtitle { column }`, `body { column }`,
  `iconAndBadge { iconColumn }`.
- A report link can pass a request: `request: DOWNLOAD` inside the link's
  `target: {}` validates, and APEX adds the checksum.

## Region layout

- **Centre a region-body button with the grid**, not its alignment.
  `layout { alignment: center }` validates and leaves it on the left. Use
  `column: 5` + `columnSpan: 4` with the `t-Button--stretch` template
  option, so the button fills the middle third.
- A region draws its items and buttons before its text. To put the region's
  HTML source above its items, set `appearance { renderComponents: belowContent }`.
- **Grid spans collapse only below 480px** (Universal Theme 26.1). A
  `columnSpan: 6` region is full width on a phone in portrait but stays half
  width in a 480-639px window. For "full width when narrow, capped when
  wide", keep the region on the full grid with a CSS class:
  `.my-card { max-width: 40rem; margin-left: auto; margin-right: auto; }`.
- In a narrow card, put a field's button on the row below it, not beside it:
  on a phone the label truncates and the button overflows.

## Page aliases

- **Never use `FILES` as a page alias.** Friendly URLs put a page at
  `/ords/r/<workspace>/<app-alias>/<page-alias>`, and APEX reserves
  `…/files/` for static files, so the page answers 400 even signed out.
- To test an alias from outside, use a browser user-agent (Cloudflare
  answers 403 to bare `curl`). A normal page answers 302 to login and an
  unknown alias 404. Drawer and modal pages answer 400 when opened directly,
  so a 400 from one of those proves nothing.

## Dynamic actions on report buttons

- Buttons drawn inside a report need a jQuery-selector dynamic action with a
  dynamic event scope, or they stop working after the report refreshes.
  Spelling: `selectionType: jQuerySelector` (capital Q) and
  `jquerySelector: .my-class` under `when {}`; `eventScope: dynamic` goes in
  `execution {}`, not `when {}` (INVALID_PROPERTY otherwise). Pattern: the
  button carries `data-id`; the action confirms, then runs
  `apex.page.submit({ request: 'X', set: { ITEM: id } })`. The item it sets
  must be `sessionStateProtection: unrestricted`.

## Delete buttons on form pages

- **A button named `DELETE` makes the form's automatic row processing
  delete the row**, even without `databaseAction: delete`: the process
  reacts to the request value. Every unconditioned after-submit process then
  runs against a row that is gone, and a `SELECT INTO` raises ORA-01403 and
  rolls back the whole submit. With your own delete procedure, give the form
  process and every unconditioned process
  `serverSideCondition { type: requestIsNotContainedInValue value: DELETE }`,
  and give every after-delete path a branch away from the page.

## Dialogs / drawers

- Returning values: the `closeDialog` process takes
  `settings { itemsToReturn: [ P64_ID P64_NAME ] }` (validates, though not
  in the skill's grammar). The parent reads `this.data.P64_ID` in an
  `apexafterclosedialog` dynamic action. To select a new row in a select
  list without a refresh, append the `<option>` in JS and `setValue` it.
- A validation's `error {}` block takes `errorMessage:` (not `message:`) and
  `associatedItem: @P64_NAME` with the `@`.
- Parent pages refresh on **both** `apexafterclosedialog` and
  `apexafterclosecanceldialog` — handle both or cancel paths go stale.

## Export shapes

- **The export omits any property equal to its default**, so hand-written
  values that match a default vanish on the next pull and components may be
  reordered. That is not a regression. Before treating a pull as one,
  compare it order-insensitively against the last commit (a line multiset
  diff ignoring `*MappingIdentifier`) and check each removed value against
  the default. Old exports spelling out old non-default values
  (`bookmarkHashFunction: sha1`) are the tell.
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
  a staged copy with shared components + only the pages under test.
  `apex-validate.sh -changed` (what push runs) picks those pages itself from
  a per-file baseline, and falls back to the full tree when anything outside
  `pages/` changed. Caveat: a partial run cannot see another page that refers
  to something renamed or removed on the edited page. The server-side import
  checks the whole app and refuses it, so that case fails at push with
  nothing replaced.
- **`apex validate` passes PL/SQL that cannot compile.** A scalar subquery
  inside a PL/SQL `case` (`'x' || ( select … )`) is SQL-only syntax; the page
  validated and failed at run time with PLS-00103. Handing each process
  block to `DBMS_SQL.PARSE` through the read-only account catches syntax
  errors without executing anything. Limit: in a block with bind variables
  (nearly every APEX block) Oracle resolves names only at execute time, so a
  call to a function that doesn't exist still parses. Check package members
  separately against `DBA_PROCEDURES`.
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
- **`FILENAME_MISMATCH`**: the page filename must match the page alias,
  not its name. Renaming a page's display name does not rename the file.
  The alias is URL-facing (`f?p=APP:ALIAS`): treat it like a static ID.
- More `INVALID_LOV` / `INVALID_PROPERTY` values (read the error's valid
  list rather than guessing):
  - `settings.trimSpaces`: `leading` / `leadingAndTrailing` / `none` /
    `trailing` (not `both`).
  - Template options are per template: `t-Region--removeHeader` is invalid
    for `@/standard` on a `cards` region though valid elsewhere.
  - Regions have no static ID in APEXlang (`staticId:` is rejected). Scope
    CSS to the page or use a template option.
  - `markdownEditor` items take no `appearance.height`.
  - "Value Identifies Row" is a column block
    `accessibility { valueIdentifiesRow: true }` on classic, IR and IG
    columns; top-level `valueIdentifiesRow:` is rejected.
  - App security values: `bookmarkHashFunction: sha2-256bit | sha2-384bit |
    sha2-512bit` (not `sha512`), `htmlEscapingMode: extended`,
    `referrerPolicy: strictOrigin`; app items take
    `security { escapeSpecialChars: true }`.
  - Classic report `type: hiddenField` is deprecated; `type: hidden` takes
    no `sorting {}` block.
  - An IG column `default { type: expression }` takes `plsqlExpression:`,
    not `expression:`.
- Removing a plug-in: delete its folder under
  `shared-components/plugins/<type>/` AND its `componentSetting` block
  (`name: plugin/<name>`) in `component-settings.apx`.
- Turning compatibility JavaScript off: omit `includeLegacyJavascript` and
  set `includeJqueryMigrate: false` under `application.apx` `javaScript {}`.
  First grep page and plug-in JS for `$x_`, `$f_`, `$d_`, `html_`, `.bind(`,
  `.live(`, `.size()`, `$.trim`, `$.browser`.

## Advisor findings that are usually false positives

- "Button is not compatible with Dynamic Actions" on the Universal Theme
  Text template: the template has `id="#DOM_ID#"` and the actions work.
- "References with Substitution Syntax … does not exist" for `&COLUMN.` in a
  cards region: the Advisor doesn't see cards columns. Both findings repeat
  per button, so the counts look worse than they are.
- "Report has Default Order" reads the SQL only; a saved-report `sort (`
  block doesn't satisfy it. Add `order by` where the default order matters.
- "Page Action on Selection" is flagged whatever the label says. Set no
  `pageActionOnSelection`, add the filter item to `pageItemsToSubmit`, and
  refresh from an item-change dynamic action.
- "Protected items in Ajax calls": a primary-key item with
  `checksumRequiredSessionLevel` and `storage: session` is already in session
  state; drop it from `pageItemsToSubmit` (the bind still works).

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
- A button slot valid on one region can warn on its sibling when they use
  different templates: `edit` exists on `@/standard` but not on
  `@/interactive-report`, so the button doesn't render there. Aligning the
  region templates fixes it.
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
- **APEX 26.2 adds file-level import**: `apex import -input <app-dir>
  -files <file> …` for pages and some shared components (not themes,
  templates or plug-ins). The app must already exist, and the export must
  come from 26.2. Oracle positions it for development and testing. Not yet
  field-tested here: whether it also disables scheduled jobs, how it picks
  the target app, and what it does with deleted pages.

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
  The APEXlang export carries no alias, so pass it every time. Run
  `set define off` first if the name contains `&`, or SQLcl prompts for a
  substitution value.
- **Main may carry `supporting-objects/` the WC export lacks** — inspect
  before assuming the replace preserves them.
- Keep the drift-check export as the rollback artifact; take a classic
  export too for belt-and-braces.
- Coordinate: no teammate should have a working copy in flight across the
  replace — theirs descends from the old main.
- Afterwards: delete the promoted WC, cut a fresh one from the new main, and
  retarget the repo (the new WC gets a NEW app id: `deployments/*.json`,
  script app ids, directory name).
- **Once main has been replaced, Builder merge from the old WC is broken
  for good.** The import gives main new component IDs, so merge tries to
  re-create components main already has (`ORA-00001 …
  WWV_FLOW_LISTITEMS_STATICID_UK`) and fails on component settings ("Error
  merging changes!" on a `PLUGIN_SETTING`). Keep promoting by replace, or
  cut a fresh WC.
- The APEXlang import skips an empty native `componentSetting` (e.g. an
  unused REST data source setting): it stays in the WC and never reaches
  main.

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
- **Any wrapper feeding SQL files to SQLcl needs `set define off`** unless
  substitution is deliberately wanted. A `&` in a string literal (URLs,
  `'&end_date='`) triggers "Substitution cancelled" — and because earlier
  statements in the file already ran, the file is left **partially applied**,
  the worst state for a run-once migration. (Bit `ro.sh` first, then
  `migrate.sh`; both now set it.)
- **A blank line inside a multi-line SQL literal ends the statement**
  (`ORA-01756: quoted string not properly terminated`) unless the script
  says `set sqlblanklines on`. A line starting with `#` at column 1 is read
  as a SQLcl command. Migrations that seed text: put `set sqlblanklines on`
  at the top, indent text lines one space, and guard new-table DDL so a
  re-run after a partial failure heals instead of failing on "already
  exists".
- Terminal discipline: paste one command at a time, never including the
  prompt (`$`, `>`, `SQL>`); hand long connect strings to `sql` as a bash
  argument — line wrap at the SQL prompt inserts real newlines into strings.

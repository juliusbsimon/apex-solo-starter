# __APP__ — __APP_TITLE__

APEX 26.1 application (app id **__APP_ID__**, workspace **__WORKSPACE__**) version-controlled
as APEXlang. The App Builder and this repo are round-tripped with the scripts
below; the repo mirrors the Builder, edits flow both ways — but never at the
same time.

## Layout

- `apex/__APP__/` — the APEXlang export, verbatim. Pages in `apex/__APP__/pages/`
  (one `.apx` per page), shared components in `apex/__APP__/shared-components/`.
- `apex/__APP__/.apex/apexlang.json` — generated metadata. **NEVER modify.**
- `apex/__APP__/deployments/*.json` — per-environment app IDs. Edit only when
  adding an environment.
- `db/` — PL/SQL sources as re-runnable `CREATE OR REPLACE` scripts.
- `db/migrations/` — ordered, run-once DDL/data scripts, named
  `YYYYMMDD-nn-description.sql`.
  (If the project adopts SQLcl Projects instead: `.dbtools/` is committed
  config, `src/database/` holds per-object exports maintained by
  `project export`, and `dist/` is generated — never hand-edited.)
- `scripts/pull.sh` / `scripts/pull.ps1` — Builder → repo (export + mirror).
- `scripts/push.sh` / `scripts/push.ps1` — repo → Builder (validate, then import). **Human-only.**
- `tmp/` — export staging, gitignored. Ignore its contents.

## Access boundaries (enforced in `.claude/settings.json` — do not work around)

- You have **no database connection**. `sql /nolog` for `apex validate` is the
  only SQLcl use permitted. Never attempt `sql -name <anything>`.
- If `sql` is not on PATH (non-interactive shells don't source `.bashrc`),
  SQLcl lives at `~/sqlcl/bin/sql` on WSL/Linux. The `scripts/*.sh` wrappers
  already handle this — prefer them over calling `sql` directly.
- Before asking the human to run a migration, **pre-flight it read-only** via
  `scripts/ro.sh`: query the data dictionary (`all_tables`, `all_tab_columns`,
  `all_objects`) to confirm referenced objects exist and new names don't
  collide. Executing the migration remains the human's step.
- After the human runs a migration or compiles code, **check the result
  yourself**: `dba_errors` for compile errors and `dba_objects` where
  `status = 'INVALID'` (filter both by the app schema). Do NOT use
  `user_errors`/`all_errors` — they are silently empty for objects this
  account cannot execute, which looks like success and is not.
- The pull, push, and **migrate** scripts (`.sh` and `.ps1`), `project deploy`, and `project release` are human-only.
- **Never suggest or configure SQLcl as an MCP server** (`sql -mcp`). MCP
  bypasses this repo's permission rules and would expose write-capable
  connections. The `ro` wrapper is the only database transport.
- To query the database (does a column exist? what shape is the data?), use
  `scripts/ro.sh "<sql>"` or `scripts/ro.sh <file.sql>` for multi-statement
  checks (PowerShell: `ro.ps1 -Query`/`-File`) — it runs through the CLAUDE_RO read-only
  account. That is your only database door; it can only read, and that is by
  design, not an obstacle to engineer around. Anything needing more, ask the
  human. End every statement you pass it with `;` (the wrapper appends one if
  missing, but multi-statement files are your responsibility). If it errors
  with ORA-01435 or `all_tables` looks unfamiliar, STOP — the saved
  connection points at the wrong database; tell the human.

## Iron rules

1. **Pull before editing.** Run `scripts/pull.sh` (WSL) or `scripts/pull.ps1` (Windows) (and check `git status` is
   clean) before touching anything under `apex/`. Never edit a stale export —
   Builder changes made since the last pull would be silently lost on push.
2. **Never run a push script** (`push.sh` / `push.ps1`). An APEXlang import **replaces the entire
   application** in App Builder. You edit and validate; the human reviews
   `git diff` and pushes.
3. **Validate before declaring done.** After any `.apx` edit:
   `sql /nolog` then `apex validate -input apex/__APP__` — iterate until
   `Validation successful`. Ask the human to run it if you cannot.
4. **Never touch `apex/__APP__/.apex/apexlang.json`** — editing it breaks
   validation. It is committed, but only the export writes it.
5. **Migration before dependent app change.** A page referencing a new column
   imports fine and fails at runtime — the `db/migrations/` script ships first.
6. **Static IDs are permanent.** Never rename an existing component's static
   ID; code and diffs depend on them. New components get readable, unique
   static IDs.
7. **Page numbers**: new pages continue the existing numbering; check
   `apex/__APP__/pages/` for the highest `pNNNNN-` before creating one.
8. **Never write a literal secret into any file** — no passwords, tokens, or
   keys, ever, in any tracked or untracked file. `db/create-claude-ro.sql`
   prompts for its password at run time BY DESIGN; if an interactive prompt
   blocks something you're doing, that script was not yours to run — report
   the obstacle to the human, do not remove it.

## APEXlang editing notes

- One file per page (`p00010-home.apx`); ALL LOVs share
  `shared-components/lovs.apx`, all lists share `lists.apx`, etc. — edits to
  one shared component touch a file containing every one of its type.
- Embedded code uses fenced blocks (```sql, ```plsql, ```javascript-browser).
- **Never put non-ASCII characters in embedded SQL/PLSQL literals** — build
  them with `chr()` / `unistr()` codepoints instead (encoding boundaries in
  the round-trip mangle raw special characters silently).
- Cross-references use `@static-id` locally and `@/name` for global/theme
  components; bind variables (`:P10_ID`, `&APP_ID.`) are unchanged.
- **`docs/apexlang-notes.md` is the first reference** — field-tested quirks
  from this codebase. When it and a skill disagree, the notes win; when both
  are silent, copy the shape of an existing validated page. Append to the
  notes whenever validation teaches you something new.
- If the Oracle `apex` skill is installed (`skills list` shows it), follow it
  for syntax; it is authoritative over guesses.

## Judgment boundaries (fix mechanically vs ask first)

- Renaming a duplicate `buttonName`, deleting a column-less `sort`/
  `displayColumn` block, mapping legacy enum values: mechanical, fix and note.
- **Removing an `authorizationScheme` reference — even a dangling numeric
  one — is a security decision: ask the human.** Same for anything touching
  authentication, session protection, or email escaping.
- Deprecated ≠ dead: before deleting a deprecated property, determine whether
  it still changes runtime behavior (see docs/apexlang-notes.md, "Cleaning up
  deprecation warnings"). When the answer needs data or trigger inspection,
  do the read-only checks; when it stays ambiguous, keep and document.

## PL/SQL conventions

- **`SQLERRM` / `SQLCODE` never appear inside a SQL statement** (INSERT,
  UPDATE, SELECT...) — that raises PLS-00231. Capture them into local
  variables in the exception handler first, then use the variables:
  `v_msg := substr(sqlerrm, 1, 4000);` then `insert ... values (v_msg)`.
  Same rule for any PL/SQL-only function.
- Exception handlers that log **re-raise** unless the swallow is explicit
  and commented — `when others then null;` is never acceptable bare.

## Commit style

`feat(p53): …` · `fix(lov): …` · `db(pkg): …` · `chore(apex): …` — feature
granularity, ticket in brackets when one exists. Do not commit `tmp/`, zips,
or `apex-exports/`.

## Known landmines (learned the hard way)

- `ORA-01403` from `WWV_META_META_DATA` during export = a component somewhere
  has incomplete metadata (see the solo runbook's troubleshooting table for
  the bisection recipe). The SQL split export
  (`apex export -applicationid __APP_ID__ -split -skipExportDate`) still works when
  APEXlang doesn't.
- SQLcl export fails with `'other' has different root` if staging and repo are
  on different drives — that's why staging lives in `tmp/` inside the repo.
- An App Builder "export" that won't unzip is an HTML error page saved under
  the export's filename — look inside before trusting it.

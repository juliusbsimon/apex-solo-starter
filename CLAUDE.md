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
- `scripts/pull.ps1` — Builder → repo (export + mirror).
- `scripts/push.ps1` — repo → Builder (validate, then import). **Human-only.**
- `tmp/` — export staging, gitignored. Ignore its contents.

## Access boundaries (enforced in `.claude/settings.json` — do not work around)

- You have **no database connection**. `sql /nolog` for `apex validate` is the
  only SQLcl use permitted. Never attempt `sql -name <anything>`.
- `pull.ps1`, `push.ps1`, `project deploy`, `project release` are human-only.
- To query the database (does a column exist? what shape is the data?), use
  `scripts/ro.ps1 -Query "<sql>"` — it runs through the CLAUDE_RO read-only
  account. That is your only database door; it can only read, and that is by
  design, not an obstacle to engineer around. Anything needing more, ask the
  human.

## Iron rules

1. **Pull before editing.** Run `scripts/pull.ps1` (and check `git status` is
   clean) before touching anything under `apex/`. Never edit a stale export —
   Builder changes made since the last pull would be silently lost on push.
2. **Never run `scripts/push.ps1`.** An APEXlang import **replaces the entire
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

## APEXlang editing notes

- One file per page (`p00010-home.apx`); ALL LOVs share
  `shared-components/lovs.apx`, all lists share `lists.apx`, etc. — edits to
  one shared component touch a file containing every one of its type.
- Embedded code uses fenced blocks (```sql, ```plsql, ```javascript-browser).
- Cross-references use `@static-id` locally and `@/name` for global/theme
  components; bind variables (`:P10_ID`, `&APP_ID.`) are unchanged.
- If the Oracle `apex` skill is installed (`skills list` shows it), follow it
  for syntax; it is authoritative over guesses.

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

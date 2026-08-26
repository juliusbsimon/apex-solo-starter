# APEX solo-project runbook — APEXlang + Git (26.1)

**Scope:** any single-developer APEX 26.1 application. This runbook ships inside the project template — if you arrived via *Use this template* → `init`, every placeholder below (`<app>`, `<APP_ID>`, `<CONN>`) was already stamped into the scripts and `CLAUDE.md` for you, and the manual-setup sections are reference, not tasks. New to Git? Read [GETTING-STARTED.md](GETTING-STARTED.md) first. Team-scale projects need a different model; this runbook is for one developer.

**Updating an existing project to the latest template:** run
`bash scripts/update-from-template.sh` from the project root (old projects
that predate the script: clone the template to `/tmp/starter` and run it from
there — the header comment has the exact lines). It overwrites template-owned
scripts, adds new pieces, side-copies anything you may have customized as
`*.template.new` for hand-merging, and re-stamps everything.

**Windows and Linux/WSL:** every script ships in both forms — `scripts/*.ps1` and `scripts/*.sh` (bash). The workflow is identical; examples below show PowerShell, substitute `./scripts/pull.sh` etc. on WSL. Two WSL notes: install SQLcl *inside* WSL (its saved-connection store is per-OS-user, so `connect -save` must be run there even if a Windows SQLcl exists), and keep the repo on the WSL filesystem (`~/dev/...`) rather than `/mnt/c/...` for git and rsync speed.

**Placeholders used throughout:** `<app>` (short lowercase name, e.g. `timesheets`) · `<APP_ID>` (DEV application id) · `<CONN>` (saved SQLcl connection, e.g. `TIMESHEETS_DEV`).

Being the only developer removes every hard problem: no working copies, no page locks, no application-lock protocol, no merge lists. What's left is a loop you can hold in your head:

> **Builder work → pull → commit.  File work → pull → edit → validate → push.  Never both at once.**

The one rule that survives from the team world: **an APEXlang import replaces the whole application.** Solo, the only person you can overwrite is yesterday's you — but that's exactly who Git is protecting.

---

## 1. One-time machine setup (once per PC, not per project)

Scripted: on WSL/Linux run `./scripts/setup-prereqs.sh` (installs JDK 21, git, rsync, and the latest SQLcl into `~/sqlcl`, and is the re-run path for SQLcl updates); on Windows run `.\scripts\check-prereqs.ps1` to verify and get install commands. The list below is what those scripts cover.

- **SQLcl 26.x** on PATH (`sql -V` to confirm). Needs JDK 17+.
- **Git.**
- **An editor — pick either or both:**
  - **VS Code** + **Oracle SQL Developer Extension for VSCode** (Marketplace, publisher Oracle) — the interactive experience: live validation squiggles, Ctrl+Space completion against real component properties, hover docs, page-lock indicator, one-click import. In its settings (Extensions → Oracle SQL Developer Extension for VSCode → APEXlang): turn **Export Before Import** ON, Export Location default (`apex-exports`), retention ~10 — snapshots the Builder version before every import, your undo button.
  - **Claude Code** in the repo folder — agent-assisted editing (see §3b). `.apx` is plain text and `apex validate` is the same authority the extension uses, so nothing in the workflow requires VS Code.

## 2. One-time project setup (~15 minutes per project)

### Setup at a glance (the checklist `init` prints, kept here for reference)

```
1. Save the connection (the workspace's PARSING SCHEMA), inside WSL if that's
   where you work — SQLcl's connection store is per-OS-user:
     sql /nolog
     connect -save <CONN> -savepwd schema/<password>@//host:1521/service
2. Agent read-only account (recommended): run db/create-claude-ro.sql as an
   admin user — it prompts for a password, nothing to edit — then:
     connect -save <APP>_CLAUDE_RO -savepwd <APP>_CLAUDE_RO/<pw>@//host:1521/service
   (per-project name: SQLcl saved connections are GLOBAL to the OS user — a
   generic CLAUDE_RO gets silently reused by another project's ro.sh and
   connects to the wrong database)
3. Baseline:   ./scripts/pull.sh   → review → git add -A && git commit
4. Remote:     git remote add origin <url> && git push -u origin main
5. Determinism check: pull again → git status must be clean
6. Validate:   ./scripts/apex-validate.sh — a long-lived app's baseline often
   carries Builder-side errors; the push gate is closed until they're fixed
```

Details for each step follow below.


> **Started from the template repo?** (GitHub → *Use this template* → clone →
> `./init.sh` / `.\init.ps1`) Then **§2.2 and §2.3 are already done** — init
> created the folder layout, stamped the scripts, and set up git. Do §2.1
> (the connection), then jump to §2.4 (baseline) and §2.5 (agent account).
> The sections below are the manual path, kept for reference and for
> understanding what init did on your behalf.

### 2.1 Save a connection

```powershell
sql /nolog
SQL> connect -save <CONN> -savepwd schema/<password>@//host:1521/service
SQL> exit
```

Connect as the workspace's **parsing schema**. Connection names are
**case-sensitive** — save them with exactly the casing the stamped scripts
expect (`grep CONN scripts/*.sh` or `scripts\*.ps1` shows the authoritative
spelling; `connmgr list` shows what's actually saved). For APEXlang *import* the workspace also needs ORDS 26.1.1+ and at least one REST-enabled schema — if the first import fails, that's the first thing to check.

### 2.2 Repo skeleton

```powershell
mkdir C:\dev\<app>
cd C:\dev\<app>
git init -b main
mkdir apex, db\migrations, scripts
```

```
<app>/
├─ .gitattributes
├─ .gitignore
├─ apex\<app>\          ← the APEXlang export lands here, verbatim
├─ db\                  ← packages, views, DDL for this project
│  └─ migrations\       ← ordered, run-once change scripts
└─ scripts\
   ├─ pull.ps1
   └─ push.ps1
```

Keep the app under `apex\<app>\`, never at the repo root — `apex export -force` deletes its target directory before writing, and it must never be pointed at a folder containing `.git`.

`.gitattributes` (prevents whole-file CRLF diffs on Windows):

```
* text=auto eol=lf
*.apx  text eol=lf diff
*.sql  text eol=lf diff
*.json text eol=lf diff
*.ps1  text eol=crlf
*.png  binary
*.zip  binary
```

`.gitignore`:

```
*.zip
*.log
/tmp/
apex-exports/
*.env
Thumbs.db
```

Note what is **not** ignored: `apex/<app>/.apex/apexlang.json` must be committed (and never hand-edited — it records the meta-metadata version, and editing it breaks validation).

### 2.3 The scripts (shipped; reference only)

The template ships four scripts, each in PowerShell and bash: `pull` (Builder → repo), `push` (repo → Builder), `apex-validate` (no DB connection needed), and `ro` (read-only DB queries for the agent, §2.5). Don't retype them from a document — the shipped copies are the maintained ones. What matters is *why* they're shaped the way they are:

- **`pull` stages inside the repo** (`tmp/`, gitignored), never `%TEMP%` — SQLcl's export throws `'other' has different root` when the stage and working directory sit on different drives.
- **`pull` guards before mirroring**: the export must contain `application.apx` or nothing is copied — a half-written export must never be mirrored over the repo, because the mirror deletes files that vanished from the source (that's also what makes deleted pages disappear from Git correctly).
- **Native commands are exit-code-checked explicitly** — `$ErrorActionPreference`/`set -e` do not catch `sql`, `git`, or `robocopy` failures; the `whenever sqlerror/oserror exit failure` header inside the SQLcl heredoc is what makes a failed export report as one.
- **`push` refuses to import unless `apex validate` passes** — the destructive operation is gated twice (validation here, and APEX validates again on import).

### 2.4 Baseline — and validate it immediately

```powershell
.\scripts\pull.ps1
git add -A
git commit -m "chore: baseline APEXlang export of <app>"
git remote add origin <url>       # a remote is your only offsite backup - don't skip it
git push -u origin main
```

**Then run `./scripts/apex-validate.sh` before anything else.** A fresh export of a long-lived app frequently carries **Builder-side errors** — duplicate button names, orphan items pointing at another page's region — that the Builder tolerated for years but validation does not. One field case: 10 errors in the baseline export. Until they're fixed, the push gate rejects everything and nobody knows why. Fix them in the Builder (or the files), re-pull, commit; *then* the workflow is open for business. The validate script prints a per-file error count so a long dump stays readable.

### 2.5 The read-only agent account (part of standard setup)

Create `CLAUDE_RO` so the agent can answer its own schema questions (does this column exist? what shape is the data?) without ever holding a key that writes. Ships alongside this runbook as `create-claude-ro.sql` — run it **as an admin user** (on RDS: the master user) — it **prompts for the password, hidden**, so there is nothing to edit in the file and nothing stored in Git. Then save the connection:

```powershell
# save the connection once - NAME IT PER PROJECT: saved connections are
# global to the OS user, and a generic CLAUDE_RO gets silently reused by
# another project's ro.sh against the wrong database (symptom: ORA-01435
# from the wrapper's alter session, unfamiliar schemas in all_tables)
sql /nolog
SQL> connect -save <app>_CLAUDE_RO -savepwd <app>_claude_ro/<password>@//host:1521/service
SQL> exit
# scripts/ro.sh / ro.ps1 (ship alongside, stamped with the name) are the
# agent's only door to it; the wrapper's `alter session set current_schema`
# doubles as the wrong-database alarm
```

Design notes, because each is deliberate:

- The account gets `CREATE SESSION` + **`READ`** (not `SELECT`) on the schema's tables and views — `READ` can't even `SELECT ... FOR UPDATE` — plus `quota 0`, so it can own nothing. Worst case is a read.
- **Grants don't cover future objects.** Re-run the grant block in `create-claude-ro.sql` after adding tables — put it in the migration checklist.
- The agent reaches it only through the `ro` wrapper (`ro.sh` / `ro.ps1`). This indirection matters: the repo's `.claude/settings.json` **denies `sql -name*` outright, and deny beats allow** in Claude Code's permission model — so the read-only connection can't be allowed directly without also loosening the deny. The wrapper is the single allowed door (`"Bash(*ro.sh*)"` / `"Bash(*ro.ps1*)"` in the allow list), and the account behind the door is harmless by construction.
- Verify the boundary once after setup: as `CLAUDE_RO`, a `select` works, a `create table` and a `delete` both fail.

---

## 3. The daily loop

### Builder work (most days)

Build in App Builder as usual. At every natural stopping point — end of a feature, end of the day:

```powershell
.\scripts\pull.ps1     # then read the diff: it's your own change log
git add -A
git commit -m "feat(p12): timesheet approval flow"
git push
```

Commit at feature granularity, not week granularity — `git log -p apex/<app>/pages/p00012-*.apx` is only useful history if commits are small. This is also your safety net: **before trying anything risky in the Builder, pull and commit first.** Then the experiment is free.

### File work (bulk edits, find-and-replace, AI-assisted refactors)

```powershell
.\scripts\pull.ps1                # ALWAYS fresh files first - never edit a stale export
git add -A; git commit -m "chore: pre-edit sync"
# ... edit .apx in VS Code (Ctrl+Space completion, Problems panel validates live) ...
.\scripts\push.ps1                # validate + import
# smoke-test in the browser
.\scripts\pull.ps1                # re-export what APEX actually stored
git add -A; git commit -m "refactor: rename all shipment refs"
```

The final pull-and-commit matters: APEX normalises things on import, and you want Git to hold what the Builder now holds, not your pre-import text. The VS Code play button (attach connection → play icon) does the same as `push.ps1` if you prefer the GUI — save the file first, it won't import unsaved buffers.

**The only way to lose work solo** is editing in *both* places without a pull in between — Builder changes made after your last pull are erased by the next push. The "pull first" habit at the top of file work eliminates it. If you do slip: the extension's Export-Before-Import snapshot (in `apex-exports/`) has the Builder version; diff, unify, re-import.

### Database code — two tiers, pick by project

APEXlang does not version database objects; that half needs its own mechanism.

**Tier 1 — hand-rolled (fine for a small, slow-moving schema):** `db/` holds current-state `CREATE OR REPLACE` sources; `db/migrations/YYYYMMDD-nn-*.sql` holds ordered, run-once DDL/data changes. You are the tracking system. Migration runs before the app change that needs it — via **`scripts/migrate.sh <file> [ADMIN_CONN]`** (human-only, like push): it runs the file, then refreshes CLAUDE_RO's grants automatically, the forget-prone step that otherwise leaves the agent blind to new tables. Conventions: `db/migrations/README.md`.

**Tier 2 — SQLcl Projects (adopt when the schema evolves actively):** SQLcl's built-in CI/CD workflow (`project` command, SQLcl 24.3+, use 26.x). It exports schema objects to per-object files, generates Liquibase changesets from **git diffs between branches**, and tracks deployments in `DATABASECHANGELOG` so nothing applies twice.

One-time setup, inside the repo:

```
sql -name <CONN>
SQL> project init -name <app>-db -schemas <SCHEMA>
SQL> project export                -- pulls objects into src/database/<SCHEMA>/<TYPE>/
SQL> exit
git add -A && git commit -m "db: baseline SQLcl project export"
```

Then two tidy-ups the tool doesn't do for you:

- **`project init` appends its boilerplate to an existing `README.md`** ("Example Template… It's fun and easy!") rather than leaving it alone — strip that before committing, your README is not a scratchpad.
- **Update `CLAUDE.md`'s layout section** to reflect the shift: `db/` conventions give way to `.dbtools/` (committed config), `src/database/` (per-object exports via `project export`), and `dist/` (generated — never hand-edited). The template's CLAUDE.md carries this as a parenthetical; adopting Projects is the moment to promote it to the actual description.

For an **existing populated schema**, baseline the target with `liquibase changelog-sync` rather than deploying release one — otherwise the first deploy tries to re-create everything.

The loop (git-driven — Projects detects change by diffing your branch against the base branch, default `master`; set yours with `project config set -name git.defaultBranch -value main`):

```
git checkout -b db/add-vessel-draft-col
-- make schema changes in the DB --
SQL> project export                -- repo catches up (this is the db-side pull.ps1)
git commit
SQL> project stage                 -- changesets generated into dist/next/ from the branch diff
git commit ; merge to main
SQL> project release -version 1.1.0
SQL> project gen-artifact
SQL> project deploy -file artifact/<app>-db-1.1.0.zip   -- connect to the target first
```

Gotchas that bite first-timers: **drops are generated commented-out** (review and uncomment deliberately); **DML isn't auto-tracked** (use `project stage add-custom -file-name <file>` for data changes); exclude `DBTOOLS$%` tables in `.dbtools/filters/project.filters` (and mind the fussy trailing-comma syntax there); commit `.dbtools/` — it's config, not scratch.

**Boundary with APEXlang — the exclusion must be EXPLICIT.** SQLcl Projects treats APEX apps as schema objects and exports them **by default**: with no filter, `project export` pulls *every app in the workspace*, in both APEXlang and full APPLICATION_SOURCE (field case: 1.2 GB of duplicated app exports next to 29 MB of actual database objects). Right after `project init`, add to `.dbtools/filters/ddl.filters`:

```
export_type not in ('APEX_APPLICATIONS','APEX'),
```

(mind the trailing comma — the filter parser requires it). The app stays governed by `pull.sh`/APEXlang; Projects handles only database objects. One repo, two lanes, no double-tracking — but the fence has to be built, not assumed.

### 3b. Working with Claude Code instead of (or alongside) VS Code

The repo is the interface — an agent editing `.apx` files sits in exactly the same loop as you do, with `apex validate` as the impartial gate. Three pieces of setup:

**The project's own field notes beat any skill.** `docs/apexlang-notes.md` holds APEXlang specifics learned from real validation failures (drawer pages use `contentBody`, IGs need a `savedReport` with `displayColumns`, date-picker binds are strings, and more) — plus the standing rule that the best reference is an existing validated page in this app. Append to it whenever validation teaches you something. Optionally keep known-good page exports in `templates/` as scaffolds for new pages (`templates/README.md`). `docs/` is also the home for source documents (specs, sample files) — binary formats there are marked in `.gitattributes` so they don't churn line endings.

**Give it the APEXlang skill.** Oracle publishes agent skills that teach the `.apx` grammar and the database conventions:

```
# from SQLcl (right-click connection → Open SQLcl, or just sql -name <CONN>):
SQL> skills sync -skill-name apex,db
SQL> skills list
```

(alternative: `npx skills add oracle/skills/apex` and `npx skills add oracle/skills/db`). Without the skill, the agent guesses at property names; with it, it knows them. **Re-run `skills sync` every few weeks** — the skills are updated alongside APEX releases.

> ⚠️ **Do NOT configure SQLcl as an MCP server** (`claude mcp add ... sql -mcp`), even though Oracle's getting-started material suggests it. MCP tool calls are not Bash commands — they bypass the `.claude/settings.json` deny rules entirely, giving the agent direct access to **every saved connection, including the write-capable ones**. That undoes the entire access-boundary design in one config line. The `ro.sh` / `ro.ps1` wrapper is the supported door; if the agent needs more DB reach, widen CLAUDE_RO's grants, not the transport.

**The house rules live in `CLAUDE.md`.** Template users: **it already exists** — the template ships it and `init` stamped your app name, ID, and workspace into it; read it once so you know what your agent has been told, and edit it as the project grows its own conventions. Manual-path users: create it in the repo root; this is the minimum viable version (the template's copy is the full worked example):

```markdown
# <app> — APEX 26.1 APEXlang project

- ALWAYS run `scripts/pull.sh` (or `scripts/pull.ps1`) before editing anything
  under apex/ — never edit a stale export.
- Never modify `apex/<app>/.apex/apexlang.json` — it is generated metadata.
- After editing .apx files, run `scripts/apex-validate.sh` (or the .ps1, or
  `apex validate -input apex/<app>` via `sql /nolog`) and iterate until
  "Validation successful".
- NEVER run a push script (`push.sh` / `push.ps1`) — importing replaces the
  entire application in the Builder. Editing and validating are yours;
  pushing is the human's, after reviewing `git diff`.
- Database code lives in `db/` (CREATE OR REPLACE current-state) and
  `db/migrations/` (ordered, run-once). A migration ships before the app
  change that depends on it.
- Commit at feature granularity with `feat(pNN): ...` / `fix: ...` /
  `db(pkg): ...` messages.
```

The same applies to the guardrails below: **template users already have `.claude/settings.json`** — the deny/allow rules ship in the template and cover both shells. The section explains what they do and why, so you can maintain them; there is nothing to install.

**Keep the push human.** The one destructive command stays a button you press after reading the diff. The loop:

```
pull.ps1  →  tell Claude Code what to change  →  it edits + validates until green
→  you read `git diff`  →  push.ps1  →  smoke-test  →  pull.ps1  →  commit
```

Same shape as the VS Code loop with the agent as editor. VS Code stays useful for hand-editing when you want the interactive experience; it's an option, not a dependency.

**Useful prompt pattern — scoped fixes.** When a push/import fails, feed the error back with an explicit blast-radius limit:

> The following error occurred during import: `<paste error>`. Analyze and fix **only the failing APEXlang source or directly related file. Do not modify unrelated components.**

The constraint matters: without it, agents "helpfully" refactor neighbors while fixing the error, and your diff review gets noisy exactly when you need it clean.

**No standalone SQLcl on a machine?** The VS Code extension bundles one: `~/.vscode/extensions/oracle.sql-developer-<version>/dbtools/sqlcl/bin/sql` (Windows: same path under `C:\Users\<user>\.vscode\...`, `sql.exe`). Fine as a fallback for the scripts; the standalone install from `setup-prereqs.sh` is still preferred (predictable path, updated on your schedule).

---

## 4. Deploying to TEST / PROD (if the project has them)

The app ID lives in `deployments/default.json`, not in the application files — so per-environment deployment files are the whole mechanism:

`apex/<app>/deployments/prod.json`:

```json
{ "app": { "id": <PROD_APP_ID>, "runtime": { "debugging": false } } }
```

```powershell
sql -name <APP>_PROD
SQL> apex import -input C:\dev\<app>\apex\<app> -deployment prod.json
```

Deploy from a clean, committed `main` — tag it (`git tag rel-2026.08.21`) so rollback is "import the previous tag". If the project is DEV-only, skip all of this.

---

## 5. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Import fails validation | Read the errors — the app only imports when it validates cleanly, so nothing was harmed. Fix and re-push. |
| Import fails with an ORDS/REST error | Workspace needs ORDS 26.1.1+ and a REST-enabled schema (§2.1). |
| Import fails on a workflow | 26.1 known issue: workflows with a **Parallel Branch** activity fail APEXlang import validation. |
| Push succeeded but Builder shows old version | You imported a stale export over newer Builder work. Recover from `apex-exports/` (the pre-import snapshot) or `git log`. |
| Export dies with `IllegalArgumentException: 'other' has different root` | SQLcl bug when the `-dir` target and working directory are on different drives. Stage inside the repo (`tmp\`), not `%TEMP%`. |
| Every file shows as changed in Git | Line endings — check `.gitattributes` landed before the first commit; if not, `git add --renormalize .` |
| Page Designer says "Specified page does not exist" for a page that's in the page list | Same incomplete-metadata condition as the ORA-01403 row below — the page's directory row exists but the loader can't assemble it. Same fix. |
| Pull shows changes you don't recognise | Normal after any import (APEX normalises), or you built something and forgot. Read the diff; it's always the answer. |
| APEXlang export fails with `ORA-01403` in `WWV_META_META_DATA` | **A component somewhere in the app has incomplete stored metadata** (field case: a page item created halfway — a `NATIVE_SWITCH` with no source/template/attributes — from an interrupted Page Designer save). Companion symptoms: App Builder's APEXlang "download" is an HTML error page saved under the export's name, and Page Designer shows "Specified page does not exist" for the broken page — while the classic SQL export still works, because it dumps rows without interpreting them. **Find it by bisection**: export another app (proves the instance is fine) → copy the app, delete all pages, export (works → it's a page; fails → shared components) → halve until one page remains → read its SQL single-page export for a component with far fewer properties than its siblings. **Fix**: delete the page, remove the offending `create_page_*` block from the SQL script, re-import it (single-page SQL import works within the same app + workspace), recreate the component in Page Designer. **Meanwhile**, `apex export -split -skipExportDate` is the fallback export — if you switch to it, also switch pull's completeness guard to check `f<APP_ID>/install.sql` + `application/` instead of `application.apx`, or the guard rejects a good export. |

---

## 6. Starting a brand-new app from scratch

For a green-field project you can go files-first: in VS Code's Connections navigator, right-click the **APEX** node → **Generate…** (workspace, app name, alias, folder) — SQLcl scaffolds a ready-to-edit APEXlang project with `application.apx` and deployment files. Edit, then push. Or create it in App Builder and start at §2.4. Either way, the loop from §3 takes over from the first commit.

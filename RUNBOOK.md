# APEX solo-project runbook — APEXlang + VS Code + Git (26.1)

**Scope:** any single-developer APEX 26.1 application. This is the template — copy it into each project's repo as `README.md` (or keep one copy and just follow it), fill in the three placeholders, done. Team-scale projects need a different model; this runbook is for one developer.

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

### 2.1 Save a connection

```powershell
sql /nolog
SQL> connect -save <CONN> -savepwd schema/<password>@//host:1521/service
SQL> exit
```

Connect as the workspace's **parsing schema**. For APEXlang *import* the workspace also needs ORDS 26.1.1+ and at least one REST-enabled schema — if the first import fails, that's the first thing to check.

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

### 2.3 The two scripts

`scripts/pull.ps1` — Builder → files:

```powershell
param(
  [string]$Conn  = "<CONN>",
  [int]   $AppId = <APP_ID>,
  [string]$App   = "<app>"
)
$ErrorActionPreference = "Stop"
$repo  = Split-Path -Parent $PSScriptRoot
# stage INSIDE the repo (tmp/ is gitignored): SQLcl's export writer
# relativizes paths and throws "'other' has different root" if the stage
# and the working directory are on different drives (repo on D:, TEMP on C:)
$stage = Join-Path $repo "tmp\apex-pull"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

@"
whenever sqlerror exit failure
apex export -applicationid $AppId -dir "$stage" -exptype apexlang -force
exit success
"@ | sql -name $Conn
if ($LASTEXITCODE -ne 0) { throw "export failed" }

$src = (Get-ChildItem $stage -Directory | Select-Object -First 1).FullName
if (-not $src -or -not (Test-Path (Join-Path $src "application.apx"))) {
  throw "export incomplete - not mirroring"
}
robocopy $src (Join-Path $repo "apex\$App") /MIR /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed" }

Set-Location $repo
git status --short
```

`scripts/push.ps1` — files → Builder:

```powershell
param(
  [string]$Conn = "<CONN>",
  [string]$App  = "<app>"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$path = Join-Path $repo "apex\$App"

@"
apex validate -input $path
exit
"@ | sql /nolog | Tee-Object -Variable out
if ($out -notmatch "Validation successful") { throw "validation failed - not importing" }

@"
whenever sqlerror exit failure
apex import -input $path
exit success
"@ | sql -name $Conn
if ($LASTEXITCODE -ne 0) { throw "import failed" }
```

### 2.4 Baseline

```powershell
.\scripts\pull.ps1
git add -A
git commit -m "chore: baseline APEXlang export of <app>"
git remote add origin <url>       # a remote is your only offsite backup - don't skip it
git push -u origin main
```

### 2.5 The read-only agent account (part of standard setup)

Create `CLAUDE_RO` so the agent can answer its own schema questions (does this column exist? what shape is the data?) without ever holding a key that writes. Ships alongside this runbook as `create-claude-ro.sql` — run it **as an admin user** (on RDS: the master user), then save the connection and drop in the wrapper:

```powershell
# save the connection once
sql /nolog
SQL> connect -save CLAUDE_RO -savepwd claude_ro/<password>@//host:1521/service
SQL> exit
# scripts/ro.ps1 (ships alongside) is the agent's only door to it
```

Design notes, because each is deliberate:

- The account gets `CREATE SESSION` + **`READ`** (not `SELECT`) on the schema's tables and views — `READ` can't even `SELECT ... FOR UPDATE` — plus `quota 0`, so it can own nothing. Worst case is a read.
- **Grants don't cover future objects.** Re-run the grant block in `create-claude-ro.sql` after adding tables — put it in the migration checklist.
- The agent reaches it only through `scripts/ro.ps1`. This indirection matters: the repo's `.claude/settings.json` **denies `sql -name*` outright, and deny beats allow** in Claude Code's permission model — so the read-only connection can't be allowed directly without also loosening the deny. The wrapper is the single allowed door (`"Bash(*ro.ps1*)"` in the allow list), and the account behind the door is harmless by construction.
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

**Tier 1 — hand-rolled (fine for a small, slow-moving schema):** `db/` holds current-state `CREATE OR REPLACE` sources; `db/migrations/YYYYMMDD-nn-*.sql` holds ordered, run-once DDL/data changes. You are the tracking system. Migration runs before the app change that needs it.

**Tier 2 — SQLcl Projects (adopt when the schema evolves actively):** SQLcl's built-in CI/CD workflow (`project` command, SQLcl 24.3+, use 26.x). It exports schema objects to per-object files, generates Liquibase changesets from **git diffs between branches**, and tracks deployments in `DATABASECHANGELOG` so nothing applies twice.

One-time setup, inside the repo:

```
sql -name <CONN>
SQL> project init -name <app>-db -schemas <SCHEMA>
SQL> project export                -- pulls objects into src/database/<SCHEMA>/<TYPE>/
SQL> exit
git add -A && git commit -m "db: baseline SQLcl project export"
```

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

**Boundary with APEXlang:** `project export` can technically carry APEX apps (`APEX_APP` object type), but its APEXlang integration is slated for a future SQLcl release — so keep the app in `apex/` via `pull.ps1` and keep the `application_id` filters out of `project.filters`. One repo, two lanes, no double-tracking.

### 3b. Working with Claude Code instead of (or alongside) VS Code

The repo is the interface — an agent editing `.apx` files sits in exactly the same loop as you do, with `apex validate` as the impartial gate. Three pieces of setup:

**Give it the APEXlang skill.** Oracle publishes agent skills that teach the `.apx` grammar and the database conventions:

```
# from SQLcl (right-click connection → Open SQLcl, or just sql -name <CONN>):
SQL> skills sync -skill-name apex,db
SQL> skills list
```

(alternative: `npx skills add oracle/skills/apex` and `npx skills add oracle/skills/db`). Without the skill, the agent guesses at property names; with it, it knows them.

**Drop a `CLAUDE.md` in the repo root** with the house rules. A full worked sample ships alongside this runbook (`CLAUDE.md` — adjust names and IDs per project). The minimum viable version:

```markdown
# <app> — APEX 26.1 APEXlang project

- ALWAYS run `scripts/pull.ps1` before editing anything under apex/ — never edit a stale export.
- Never modify `apex/<app>/.apex/apexlang.json` — it is generated metadata.
- After editing .apx files, run `scripts/apex-validate` (or `apex validate -input apex/<app>` via `sql /nolog`) and iterate until "Validation successful".
- NEVER run `scripts/push.ps1` — importing replaces the entire application in the Builder. Editing and validating are yours; pushing is the human's, after reviewing `git diff`.
- Database code lives in `db/` (CREATE OR REPLACE current-state) and `db/migrations/` (ordered, run-once). A migration ships before the app change that depends on it.
- Commit at feature granularity with `feat(pNN): ...` / `fix: ...` / `db(pkg): ...` messages.
```

**Guardrails — enforcement, not etiquette.** CLAUDE.md rules are advisory; the agent follows them, but real prevention lives where breaking a rule is impossible. Two layers, both cheap:

*Layer 1 — no connection, no risk.* The only SQLcl operation the agent needs is `apex validate`, which runs under `sql /nolog` — no credentials, no schema access. The saved named connections (`sql -name <CONN>`) are the keys to the database; everything that uses them (`pull.ps1`, `push.ps1`, `project export/deploy`) stays human. An agent with no connection cannot change a schema, run a migration, or touch data — the risk class doesn't exist.

*Layer 2 — enforce it at the tool layer.* Commit `.claude/settings.json` in the repo root so the rule is mechanical, travels with the repo, and can't be talked around mid-session:

```json
{
  "permissions": {
    "deny": [
      "Bash(sql -name*)",
      "Bash(*push.ps1*)",
      "Bash(*pull.ps1*)",
      "Bash(*project deploy*)",
      "Bash(*project release*)"
    ],
    "allow": [
      "Bash(sql /nolog*)"
    ]
  }
}
```

Deny rules are checked before execution and take precedence over everything else.

*Layer 3 (only if the agent should introspect the DB* — check a column exists, read data shapes*):* create a read-only account — `CREATE USER claude_ro`, grant `CREATE SESSION` plus `SELECT` on the schema's tables, nothing else — save it as its own named connection, and add `"Bash(sql -name CLAUDE_RO*)"` to the allow list. Worst case then is a read.

*Layer 4 (production, belt-and-braces):* all DDL reaches PROD only through reviewed `project deploy` artifacts run under a human connection — drops arrive commented-out by design. A DDL trigger gating schema changes on a context flag is available if policy demands it.

**Keep the push human.** The one destructive command stays a button you press after reading the diff. The loop:

```
pull.ps1  →  tell Claude Code what to change  →  it edits + validates until green
→  you read `git diff`  →  push.ps1  →  smoke-test  →  pull.ps1  →  commit
```

Same shape as the VS Code loop with the agent as editor. VS Code stays useful for hand-editing when you want the interactive experience; it's an option, not a dependency.

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
| Pull shows changes you don't recognise | Normal after any import (APEX normalises), or you built something and forgot. Read the diff; it's always the answer. |
| APEXlang export fails with `ORA-01403` in `WWV_META_META_DATA` | Engine-side bug at your instance's patch level (base 26.1 through 26.1.2 are affected; fixed in Oracle's 26.1.3+ bundles). On a managed platform (AWS RDS, OCI) you cannot patch APEX yourself — fall back to `apex export -applicationid <id> -split -skipExportDate` (SQL format, different code path, per-page files, fully diffable) until the platform ships a fixed APEX version. **When switching formats, also switch the completeness guard in `pull.ps1`**: the split export produces `f<APP_ID>\install.sql` + an `application\` folder, not `application.apx` — check for those instead, or the guard will reject a good export. A "downloaded" App Builder export that won't unzip is the same failure: it's an error page saved under the export's name — look inside before trusting it. |

---

## 6. Starting a brand-new app from scratch

For a green-field project you can go files-first: in VS Code's Connections navigator, right-click the **APEX** node → **Generate…** (workspace, app name, alias, folder) — SQLcl scaffolds a ready-to-edit APEXlang project with `application.apx` and deployment files. Edit, then push. Or create it in App Builder and start at §2.4. Either way, the loop from §3 takes over from the first commit.

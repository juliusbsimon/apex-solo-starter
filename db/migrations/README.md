# Migrations

- **Naming:** `YYYYMMDD-nn-description.sql` — date, sequence within the day,
  what it does. Run order = filename order.
- **Run-once, forward-only.** These are not re-runnable; the re-runnable
  current-state sources live in `db/` (or `src/database/` under SQLcl
  Projects). A migration that needs revising after it ran anywhere gets a
  *new* migration, never an edit.
- **Ship before the page.** The migration runs before the APEX change that
  depends on it — a page referencing a missing column imports fine and fails
  at runtime.
- **Run via `scripts/migrate.sh <file> [ADMIN_CONN]`** (human-only): it runs
  the migration and then refreshes CLAUDE_RO's grants so the agent can see
  any new tables. Forgetting the refresh is the most common way to make the
  agent mysteriously blind.

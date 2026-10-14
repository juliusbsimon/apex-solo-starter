# Migrations

- **Naming:** `YYYYMMDD-nn-description.sql` — date, sequence within the day,
  what it does. Run order = filename order.
- **Run-once, forward-only.** These are not re-runnable; the re-runnable
  current-state sources live in `db/` (or `src/database/` under SQLcl
  Projects). A migration that needs revising after it ran anywhere gets a
  *new* migration, never an edit.
- **Everything the database needs is in a migration.** That includes code:
  a new or changed procedure, function, package, trigger or view in `db/`
  gets deployed by a migration line that includes it, in dependency order:

  ```sql
  -- 20261014-02-order-code.sql
  @@../p_apply_discount.sql
  @@../pkg_orders.sql
  @@../trg_orders_biu.sql
  ```

  `@@` resolves relative to this folder, and the compile gate below checks
  the included objects too. Never hand the human a source file to "compile
  separately": a file nobody wires into a migration never reaches the
  database. `scripts/db-coverage.sh` (no database, safe for the agent) lists
  changed `db/` sources that no pending migration includes, and `migrate`
  runs it first and asks before running anyway.
- **Ship before the page.** The migration runs before the APEX change that
  depends on it — a page referencing a missing column imports fine and fails
  at runtime.
- **Run via `scripts/migrate.sh <file> [<file> ...] [ADMIN_CONN]`**
  (human-only): it runs each migration in order, stops at the first failure,
  and then — once, at the end — refreshes CLAUDE_RO's grants via
  `db/refresh-claude-ro-grants.sql` so the agent can see any new tables.
  Forgetting the refresh is the most common way to make the agent
  mysteriously blind. The refresh script has NO password prompt; the prompt
  lives only in `db/create-claude-ro.sql`, the one-time creation script.
- **Applied ledger:** each file that runs successfully is recorded in
  `applied-<CONN>.txt` here (one ledger per connection, so dev and prod
  histories stay separate). migrate skips files already in the ledger
  (`-redo` / `-Redo` forces a re-run), and the GUI hides them from its
  list. **Commit the ledger with your migration files** — it is the record
  of what that connection's database has received. Pre-existing projects
  start with an empty ledger: old, already-run migrations are only
  protected once they are listed, so don't select them (as before).
- **Compile gate:** after each file, migrate checks `user_errors` for every
  object the file created or replaced. Any error fails the run and the file
  is NOT written to the ledger (SQLcl alone reports "created with
  compilation errors" as success). Fix the source and re-run the same file:
  it wasn't recorded, so it isn't skipped. Other INVALID objects in the
  schema are listed as warnings but don't fail the run.

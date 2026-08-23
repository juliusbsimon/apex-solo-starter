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
- Filter items on drawer parents: a Change DA plus
  `warnOnUnsavedChanges: ignore`, or navigation nags about unsaved changes.

## Reports

- Classic-report columns rendering HTML need
  `security { escapeSpecialChars: false }`.
- Hidden columns take no `heading`.

## Dialogs / drawers

- Parent pages refresh on **both** `apexafterclosedialog` and
  `apexafterclosecanceldialog` — handle both or cancel paths go stale.

## Validation quirks

- A fresh export of a long-lived app may carry **Builder-side errors**
  (duplicate button names, orphan items pointing at other pages' regions).
  `apex validate` right after the baseline export tells you; the push gate is
  unusable until they're fixed. See RUNBOOK §2.4.

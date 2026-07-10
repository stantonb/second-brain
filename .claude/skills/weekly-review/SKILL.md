---
name: weekly-review
description: Compose and deliver the Sunday weekly review DM — wins, dropped balls, >30-day stale-task cull proposals, brag doc append from read-only CSD EL, and the 14-entry Journal self-check. Use for the Sunday 17:00 routine.
---

# Weekly review

Read `CLAUDE.md` in full first. Rule #1: never fail silent.

## Modes

Identical contract to `morning-briefing`:
`FIXTURE_MODE=1` (fixtures per `tests/fixtures/README.md`, no network/writes, print
review + "Would write:" list) · `DRY_RUN=1` (live reads, deliver to `#test`, run ID
suffixed `-test`, **and skip the Brag doc append** — report what would be appended
instead, so a test run never writes prose Stanton has to clean up) · production
(DM + Journal + Brag doc append).

## Procedure

0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)` — a Sunday in
   production. Week = Monday..Sunday containing TODAY (Europe/London). Run ID
   `weekly-$TODAY`; same Journal rerun check as the daily skills.
1. **Gather (reads only).**
   - The week's Journal pages: Date within the week, all Types.
   - Tasks activity: Completed within the week; created within the week; Status
     `Dropped` changes; rollover counts (properties, not prose).
   - `CSD EL` sub-pages with `last_edited_time` in the last 7 days — **READ-ONLY**;
     never touch Habit Tracker or DND.
2. **Compose** per `CLAUDE.md → ## Briefing formats → Weekly`:
   - **Wins:** completed High-priority/Work tasks; shipped items visible in the CSD EL
     updates; anything Stanton flagged during the week.
   - **Dropped balls:** rollover counts ≥ 3; missed due dates still open; `Waiting`
     items with no movement all week.
   - **Stale culls:** rolling-list tasks with age > 30 days (Last Touched, fallback
     Created), unpinned, unsnoozed → propose `Dropped`. Confirmation is a `drop:`
     capture from Stanton; the review never drops anything itself.
   - **Next week:** first meetings, due items, one-line shape.
3. **Brag doc append (production only).** Work wins (from CSD EL updates + completed
   Work tasks) as dated bullets under the current month's `## {Month} {Year}` heading
   on the Brag doc page (ID in CLAUDE.md); create the heading if missing. This is the
   only write outside the databases — still inside Second Brain.
4. **Self-check.** Expected Journal entries for the week = `morning-` and `evening-`
   for each of the 7 days (14 total; ignore `-test` pages). Report `{N}/14` and list
   every missing run ID with ⚠️. A green routine status only means the session ran —
   this check is what catches quiet failures.
5. **Deliver + journal.** Per mode; Journal page (title = run ID, Date = TODAY,
   Type = `Weekly`) with the full text — even if Discord failed.

## Never

- Write under CSD EL (or anywhere outside Second Brain); read Habit Tracker or DND.
- Drop a task without Stanton's `drop:` confirmation.
- Infer rollover/completion state from Journal prose instead of Task properties.
- Skip delivery because a service failed.

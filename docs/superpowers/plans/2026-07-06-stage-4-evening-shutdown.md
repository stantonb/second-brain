# Stage 4 — Evening Shutdown Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** An `evening-shutdown` skill (done-reconciliation, honest rollover with counts, tomorrow preview) proven against fixtures, then `#test`, then running as a real 21:00 Europe/London routine with verified real deliveries and Stanton's confirmation.

**Architecture:** Same three-mode pattern as `morning-briefing` (`FIXTURE_MODE` / `DRY_RUN` / production). The distinguishing logic: reconciling completions and mutating rollover state on Task properties (Rollover Count, Last Rolled Over, Last Touched) — never derived from Journal prose.

**Tech Stack:** Claude Code skill, Notion/Google connectors, `scripts/discord.sh`, claude.ai routines.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md`. Reality contradicts it → STOP and ask Stanton; record the agreed change with a dated note.
- Secrets only in cloud env vars + local shell. Never committed/echoed.
- Notion writes only inside Second Brain; `Habit Tracker`/`DND` never read; `CSD EL` read-only.
- All date logic explicitly Europe/London.
- Rule #1 — never fail silent.
- User-action steps: exact instructions, then STOP for confirmation.
- ✋ **CHECKPOINT:** verified real 21:00 deliveries, then STOP for Stanton's confirmation before Stage 5.
- Commit after each task.

**Prerequisite:** Stage 3 confirmed by Stanton (morning briefing running reliably).

---

### Task 1: The `evening-shutdown` skill

**Files:**
- Create: `.claude/skills/evening-shutdown/SKILL.md`

**Interfaces:**
- Consumes: `CLAUDE.md` (map, triage rules, Evening format, timezone rule), `scripts/discord.sh`, the mode contract from Stage 3.
- Produces: the run procedure for the 21:00 routine; the rollover property mutations (Rollover Count, Last Rolled Over) that the weekly review (Stage 5) reads.

- [ ] **Step 1: Write `.claude/skills/evening-shutdown/SKILL.md` with exactly this content**

````markdown
---
name: evening-shutdown
description: Compose and deliver the 9pm evening shutdown DM — capture triage incl. done/drop/snooze/waiting updates, completion reconciliation, honest task rollover with counts, tomorrow preview. Use for the daily 21:00 routine.
---

# Evening shutdown

Read `CLAUDE.md` in full first. Rule #1: never fail silent.

## Modes

Identical contract to `morning-briefing`:
`FIXTURE_MODE=1` (fixtures per `tests/fixtures/README.md`, no network/writes, print
briefing + "Would write:" list) · `DRY_RUN=1` (live reads + real triage, deliver to
`#test`, run ID suffixed `-test`) · production (DM + Journal).

## Procedure

0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)`;
   `TOMORROW=$(TZ=Europe/London date -v+1d +%F)` locally (`date -d '+1 day' +%F` on
   Linux cloud runs). Run ID `evening-$TODAY`. Same Journal rerun check as morning.
1. **Triage captures** — same protocol as morning (cursor from Capture Log, dedupe,
   Capture Log row before ✅). Evening is where `done:` / `drop:` / `snooze:` /
   `waiting:` status updates mostly land — apply CLAUDE.md rule 2's confidence gate
   strictly: ambiguous match → `Needs Review`, never guess.
2. **Reconcile completions.** Query Tasks for Status `Done` with empty Completed →
   set Completed = TODAY, Last Touched = TODAY (these are tasks Stanton ticked off in
   Notion himself). "Done today" for the DM = all tasks with Completed = TODAY,
   whether from Notion edits or `done:` captures.
3. **Honest rollover.** Query Tasks for Due ≤ TODAY with Status ∈ {`Next`,
   `In progress`, `Waiting`} (unsnoozed). Skip any task whose Last Rolled Over is
   already TODAY (rerun guard — a manual rerun must not double-increment). For each
   remaining task: Rollover Count += 1, Last Rolled Over = TODAY. Due is left unchanged — overdue is information, not
   something to hide. List each in the DM with its ordinal count ("3rd time"). Counts
   come from the Task properties just written — never parsed from Journal prose.
4. **Decisions needed.** Unresolved `Needs Review` Capture Log rows, carried forward.
5. **Tomorrow preview.** First meeting and one-line day shape from tomorrow's calendar
   across connected accounts.
6. **Compose, deliver, journal.** Compose exactly per `CLAUDE.md → ## Briefing formats
   → Evening`; omit empty sections; ⚠️ lines for unreachable services. Deliver per
   mode. Journal page (title = run ID, Date = TODAY, Type = `Evening`) with the full
   text — even if Discord failed.

## Never

- Write outside Second Brain; read Habit Tracker or DND.
- Change a Due date during rollover, or infer rollover state from prose.
- Guess on ambiguous `done:`/`drop:` matches.
- Skip delivery because a service failed.
````

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/evening-shutdown/SKILL.md
git commit -m "feat: evening-shutdown skill (reconcile, honest rollover, tomorrow preview)"
```

---

### Task 2: Fixture dry-run

**Files:** none.

- [ ] **Step 1: Run the skill with `FIXTURE_MODE=1`.**
- [ ] **Step 2: Verify against these expectations (show Stanton the output):**
  - Captured line: 1 task, 1 link, 1 needs-review (same fixtures as morning — `done: expenses` has no match, so it must land in decisions-needed, NOT mark anything done).
  - Rollover lists `Q3 roadmap draft` (fixture due 2026-07-06 ≤ today, In progress) — "Would write:" shows Rollover Count 3 → 4 and the DM line says "4th time".
  - `Renew passport` (due 2026-09-01) and undated tasks are NOT rolled over.
  - Tomorrow preview uses the calendar fixture sensibly (fixture has no tomorrow data → preview says so rather than inventing events).
  - "Would write:" itemises the rollover property updates + Capture Log rows + Journal page; zero writes outside Second Brain.
- [ ] **Step 3: Fix until expectations hold; commit**

```bash
git add -A && git commit -m "fix: evening shutdown composition against fixtures"
```

---

### Task 3: Live dry-run to `#test`

**Files:** none.

- [ ] **Step 1: Ask Stanton to add captures exercising evening paths**: a `done: <real task name>` for a task that exists in Tasks, and a `snooze: <task> until <date>`. STOP and wait.
- [ ] **Step 2: Run with `DRY_RUN=1`.** Verify with Stanton:
  - `#test` receives the shutdown, Evening format.
  - The `done:` capture marked the right task Done (Completed = today, Last Touched = today) — show the Notion row.
  - The `snooze:` capture set Snoozed Until correctly.
  - Any genuinely due-today open tasks show incremented Rollover Count in Notion — show before/after values.
  - Journal `evening-<today>-test` exists.
- [ ] **Step 3: Idempotency proof — immediately re-run `DRY_RUN=1`.** Expected: no double rollover increment (the run must not re-increment tasks whose Last Rolled Over = today — this is the property-based guard working), no re-triage, Journal updated not duplicated.
- [ ] **Step 4: Commit fixes**

```bash
git add -A && git commit -m "fix: evening shutdown live dry-run adjustments"
```

---

### Task 4: Create the routine (21:00 Europe/London)

**Files:** none (cloud config).

- [ ] **Step 1: Push all commits to `main`.**
- [ ] **Step 2: Create schedule `evening-shutdown`** via the `schedule` skill: daily 21:00, timezone Europe/London, same repo/environment as morning-briefing (env vars, custom network + `discord.com`, connectors Notion + Google only are already configured on the environment — verify they apply to this routine too; if per-routine, USER ACTION to mirror Stage 3 Task 5 Step 3). Prompt:

```text
Read CLAUDE.md, then use the evening-shutdown skill to run today's evening shutdown.
Production mode (no FIXTURE_MODE, no DRY_RUN). Rule #1: never fail silent.
```

- [ ] **Step 3: Trigger one manual run.** Verify DM + `evening-<today>` Journal page (distinct from the `-test` one).

---

### Task 5: ✋ CHECKPOINT — verified real deliveries

**Files:** none.

> **2026-07-10:** Routine created ~18:45 BST (Google Drive connector removed from both
> routines — it had attached by default). Manual run 18:50 BST: DM + `evening-2026-07-10`
> journaled via the REST write path. Scheduled run 21:11 BST: rerun path verified —
> same page updated with a rerun note, identical DM, no duplicates or double-processing.
> Stanton waived the second scheduled delivery and confirmed the same evening ("Lets
> skip the 2nd verification and say this looks good") — checkpoint closed at his call;
> Stage 5 unblocked. Mid-stage deviations recorded en route: Notion writes moved to
> notion.sh REST (spec note 2026-07-09) after the connector lost write tools in cloud
> twice; multi-intent capture rule (2026-07-08); NL-completion auto-close + relative
> dates from capture timestamp (2026-07-10).

- [ ] **Step 1: After the first scheduled 21:00 run:** Stanton confirms the DM; Journal page checked; rollover counts in Notion spot-checked against the DM's claims (honesty check — the numbers must agree).
- [ ] **Step 2: Second scheduled delivery verified the same way.**
- [ ] **Step 3: STOP.** Ask Stanton: "Evening shutdowns look right? Stage 5 (weekly review) starts only on your word." Wait.
- [ ] **Step 4: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 4 — evening shutdown routine live, real deliveries verified" --allow-empty
```

# Stage 5 — Weekly Review Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** A `weekly-review` skill (wins, dropped balls, >30-day cull proposals, brag-doc append from read-only `CSD EL`, 14-run Journal self-check) proven against fixtures, then `#test`, then live as a Sunday 17:00 Europe/London routine with a verified real delivery and Stanton's confirmation.

**Architecture:** Same three-mode pattern. New inputs: the week's Journal pages, Tasks activity, and recently updated `CSD EL` sub-pages (strictly read-only). One new write target: the Brag doc page (append under the month heading). The self-check is the system's silent-failure detector: 7 mornings + 7 evenings = 14 expected Journal entries.

**Tech Stack:** Claude Code skill, Notion/Google connectors, `scripts/discord.sh`, claude.ai routines.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md`. Reality contradicts it → STOP and ask Stanton; record the agreed change with a dated note.
- Secrets only in cloud env vars + local shell.
- Notion writes only inside Second Brain (databases + Brag doc). **`CSD EL` is read-only — reading its recently updated sub-pages is allowed and required; any write there is forbidden.** `Habit Tracker`/`DND` never read.
- All date logic explicitly Europe/London.
- Rule #1 — never fail silent.
- User-action steps: exact instructions, then STOP for confirmation.
- ✋ **CHECKPOINT:** verified real Sunday delivery → STOP for Stanton's confirmation. Then the Phase 2 gate: Stages 6–11 start only after the core has run reliably for ≥ 1 week.
- Commit after each task.

**Prerequisite:** Stage 4 confirmed by Stanton.

---

### Task 1: Weekly fixtures

**Files:**
- Create: `tests/fixtures/notion/journal-week.json`
- Create: `tests/fixtures/notion/csd-el-recent.json`

**Interfaces:**
- Produces: fixture shapes for the weekly self-check (deliberately 13 of 14 entries — one gap to detect) and the brag-doc extraction. Already listed in `tests/fixtures/README.md`'s mapping.

- [ ] **Step 1: Write `tests/fixtures/notion/journal-week.json`** — the week Mon 2026-06-29 → Sun 2026-07-05, with `evening-2026-07-02` deliberately missing (13 entries):

```json
[
  { "title": "morning-2026-06-29", "type": "Morning", "date": "2026-06-29" },
  { "title": "evening-2026-06-29", "type": "Evening", "date": "2026-06-29" },
  { "title": "morning-2026-06-30", "type": "Morning", "date": "2026-06-30" },
  { "title": "evening-2026-06-30", "type": "Evening", "date": "2026-06-30" },
  { "title": "morning-2026-07-01", "type": "Morning", "date": "2026-07-01" },
  { "title": "evening-2026-07-01", "type": "Evening", "date": "2026-07-01" },
  { "title": "morning-2026-07-02", "type": "Morning", "date": "2026-07-02" },
  { "title": "morning-2026-07-03", "type": "Morning", "date": "2026-07-03" },
  { "title": "evening-2026-07-03", "type": "Evening", "date": "2026-07-03" },
  { "title": "morning-2026-07-04", "type": "Morning", "date": "2026-07-04" },
  { "title": "evening-2026-07-04", "type": "Evening", "date": "2026-07-04" },
  { "title": "morning-2026-07-05", "type": "Morning", "date": "2026-07-05" },
  { "title": "evening-2026-07-05", "type": "Evening", "date": "2026-07-05" }
]
```

- [ ] **Step 2: Write `tests/fixtures/notion/csd-el-recent.json`** — canned "recently updated sub-pages under CSD EL":

```json
[
  { "title": "Quote engine migration", "last_edited": "2026-07-03",
    "summary": "Cutover completed for 2 of 3 product lines; error rate flat; Stanton unblocked the rating-service rollback plan." },
  { "title": "Hiring — senior platform engineer", "last_edited": "2026-07-01",
    "summary": "Two onsites completed; one strong yes. Stanton rewrote the take-home rubric after panel feedback." }
]
```

- [ ] **Step 3: Verify parse and commit**

```bash
jq -e . tests/fixtures/notion/journal-week.json tests/fixtures/notion/csd-el-recent.json > /dev/null && echo OK
git add tests/fixtures/notion
git commit -m "test: add weekly-review fixtures (journal week with a gap, CSD EL wins)"
```

---

### Task 2: The `weekly-review` skill

**Files:**
- Create: `.claude/skills/weekly-review/SKILL.md`

**Interfaces:**
- Consumes: `CLAUDE.md` (map, Weekly format, aging rules), `scripts/discord.sh`, mode contract, rollover properties written by Stage 4.
- Produces: the Sunday 17:00 run procedure; Brag doc appends.

- [ ] **Step 1: Write `.claude/skills/weekly-review/SKILL.md` with exactly this content**

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/weekly-review/SKILL.md
git commit -m "feat: weekly-review skill (wins, culls, brag doc, 14-run self-check)"
```

---

### Task 3: Fixture dry-run

**Files:** none.

- [ ] **Step 1: Run with `FIXTURE_MODE=1`.**
- [ ] **Step 2: Verify (show Stanton the output):**
  - **Self-check reports 13/14 and names `evening-2026-07-02`** — the planted gap must be caught by run ID.
  - Stale culls propose `Write blog post on routines` (fixture Last Touched 2026-06-05, >30 days, unpinned) and NOT `Renew passport` (pinned) — each with its age.
  - Dropped balls include `Q3 roadmap draft` (rollover count ≥ 3 in the fixture).
  - Wins draw on both `csd-el-recent.json` items.
  - "Would write:" lists the Journal page and the Brag doc bullets (with the exact text to append) — nothing else, and nothing under CSD EL.
- [ ] **Step 3: Fix until the expectations hold; commit**

```bash
git add -A && git commit -m "fix: weekly review composition against fixtures"
```

---

### Task 4: Live dry-run to `#test`

**Files:** none.

- [ ] **Step 1: Run with `DRY_RUN=1`** (live reads — real Journal week, real Tasks, real CSD EL recent sub-pages).
- [ ] **Step 2: Verify with Stanton:**
  - Review lands in `#test`, Weekly format.
  - Self-check numbers match reality (early in the rollout the week will be legitimately partial — the check must report the true count and name the missing run IDs, not pretend 14/14).
  - The proposed brag-doc bullets (reported, not written, in DRY_RUN) are accurate and sourced only from CSD EL reads + completed Work tasks.
  - Journal `weekly-<today>-test` exists; Brag doc page unchanged (DRY_RUN skips the append).
- [ ] **Step 3: Commit fixes**

```bash
git add -A && git commit -m "fix: weekly review live dry-run adjustments"
```

---

### Task 5: Create the routine (Sunday 17:00 Europe/London)

**Files:** none (cloud config).

- [ ] **Step 1: Push all commits to `main`.**
- [ ] **Step 2: Create schedule `weekly-review`** via the `schedule` skill: weekly, Sunday 17:00, timezone Europe/London, same repo/environment (verify env vars, custom network + `discord.com`, connectors Notion + Google only apply, as in Stage 4 Task 4). Prompt:

```text
Read CLAUDE.md, then use the weekly-review skill to run this week's review.
Production mode (no FIXTURE_MODE, no DRY_RUN). Rule #1: never fail silent.
```

- [ ] **Step 3: Trigger one manual run** (acceptable mid-week: the self-check will report a partial week honestly). Verify DM + `weekly-<today>` Journal page + Brag doc actually gained the month-section bullets (show Stanton the appended text).

---

### Task 6: ✋ CHECKPOINT — verified real Sunday delivery

**Files:** none.

> **2026-07-12:** Scheduled Sunday 17:00 run verified end-to-end (journal 17:08 BST,
> honest 8/14 self-check with every gap explained, Brag doc appended one new item
> without duplicating the mid-week manual run's entry, S–/G– calendar rule and
> capture-timestamp date rule both applied in production). Stanton confirmed
> ("Looks good") — Stage 5 closed, core complete. Phase 2 gate now applies: plans
> for Stages 6–11 are written only after a reliable week (next Sunday's self-check
> clean or all gaps explained). Also proven this weekend: Siri webhook capture
> (Phase 2 item 8, phone-side) — four dictations triaged to tasks.

- [ ] **Step 1: After the first scheduled Sunday 17:00 run:** Stanton confirms the DM; Journal page checked; self-check verified against the real Journal contents; Brag doc append verified in Notion.
- [ ] **Step 2: STOP.** Tell Stanton the core is fully live and the Phase 2 gate now applies: **Stages 6–11 start only after the core has run reliably for at least one week** (weekly self-check clean or all gaps explained). Their plans get written when he opens that gate.
- [ ] **Step 3: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 5 — weekly review routine live, core complete" --allow-empty
```

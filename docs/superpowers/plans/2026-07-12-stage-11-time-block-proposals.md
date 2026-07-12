# Stage 11 — Time-Block Proposals Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** The morning briefing suggests which of today's calendar gaps fit the Top 3 tasks — a `⏱ Time-blocks` section — **as suggestions only, never writing to the calendar.**

**Architecture:** Pure composition. Both inputs already exist in the morning-briefing procedure: the Top 3 (step 3) and the day's gaps (step 2). Stage 11 adds a `⏱ Time-blocks` section to the Morning format and a bounded matching heuristic in `CLAUDE.md`, and extends the skill's compose step to render it. No new Notion objects, no new writes, no calendar mutations — the lowest-risk Phase 2 stage.

**Tech Stack:** `CLAUDE.md` briefing format + heuristic, morning-briefing skill, existing calendar/task fixtures.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md` (Phase 2 item 6). Reality contradicts it → STOP and ask Stanton; record with a dated note.
- **No calendar writes.** Actually writing events is explicitly a separate, later decision (spec item 6) — this stage only *suggests*.
- Secrets only in cloud env vars + local shell. Notion writes only inside Second Brain; `Habit Tracker`/`DND` never read; `CSD EL` read-only.
- Shared-calendar prefixes still apply: `G –` events excluded from gaps and day-shape; `S –` and unprefixed included (CLAUDE.md, 2026-07-11).
- All date/time logic explicitly Europe/London.
- Rule #1 — never fail silent; the time-block section is additive and is simply omitted when there's nothing to place.
- ✋ **CHECKPOINT:** the section is accurate and never attempts a calendar write, then STOP for Stanton's confirmation. This closes the planned Phase 2 stages (6–11).
- Commit after each task.

**Prerequisite:** Core complete (Stages 0–5); Phase 2 planning gate open; morning briefing computes Top 3 + gaps. **Execution waits for Stanton's explicit go and the reliability bar.**

---

### Task 1: Morning format + heuristic in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (Morning briefing format; new `### Time-block proposals` note)

**Interfaces:**
- Produces: the `⏱ Time-blocks` section shape + the matching heuristic the skill renders.

- [ ] **Step 1: Add the `⏱ Time-blocks` block to the Morning format** in `CLAUDE.md → ## Briefing formats → ### Morning`, immediately after the `🎯 Top 3` block:

```markdown
**⏱ Time-blocks**   (suggestions only — no calendar changes)
- {HH:MM}–{HH:MM} → {task}
```

- [ ] **Step 2: Add a `### Time-block proposals` subsection** immediately after the `### Recurrence rules` subsection (or after `### Aging rules` if Stage 10 isn't in yet):

```markdown
### Time-block proposals (morning briefing)

The morning briefing suggests which of today's gaps fit the Top 3 — **suggestions only,
never a calendar write.** Estimate each Top-3 task's block from Priority (High ≈ 90 min,
Medium ≈ 60 min, Low ≈ 30 min, unless the task obviously implies otherwise). Walking the
day's gaps (≥ 45 min, between 09:00–18:00, `G –` events already excluded) earliest-first,
place the tasks in Top-3 order (top 1 first), one block per gap segment — a long gap may
hold two short blocks, but a block never overflows its gap. Render under `⏱ Time-blocks`
as `{HH:MM}–{HH:MM} → {task}`. Omit the whole section when there are no qualifying gaps or
no Top 3. If a Top-3 task can't be placed, leave it unplaced and add one line
("no gap today for {task}"). This never reads or writes the calendar beyond the gaps the
briefing already computed.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: time-block proposal format + heuristic (Stage 11, suggestions only)"
```

---

### Task 2: Render the section in the morning-briefing skill

**Files:**
- Modify: `.claude/skills/morning-briefing/SKILL.md` (compose step + `## Never`)

**Interfaces:**
- Consumes: the Top 3 (procedure step 3) and gaps (procedure step 2); the heuristic from Task 1.
- Produces: the rendered `⏱ Time-blocks` section, no calendar writes.

- [ ] **Step 1: Extend the compose step** (the `Compose, deliver, journal` step) — add this sentence to its "Compose" bullet:

```markdown
Include the `⏱ Time-blocks` section: match each Top-3 task to a suitable calendar gap per
`CLAUDE.md → Time-block proposals` (suggestions only — never write to the calendar). Omit
the section when there are no gaps or no Top 3.
```

- [ ] **Step 2: Add a guard to `## Never`** in the morning-briefing skill:

```markdown
- Write to (create/move/update) any calendar event — time-blocks are suggestions only.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/morning-briefing/SKILL.md
git commit -m "feat: morning briefing renders time-block suggestions (no calendar writes)"
```

---

### Task 3: Fixture-mode verification

**Files:** none (reuses `google/calendar-today.json` + `notion/tasks.json`).

- [ ] **Step 1: Run the morning-briefing skill with `FIXTURE_MODE=1`.**
- [ ] **Step 2: Verify against these expectations (show Stanton the output):**
  - A `⏱ Time-blocks` section appears with the "suggestions only — no calendar changes" note.
  - The **top-1 task** (`Q3 roadmap draft`, High) is placed in the **earliest** qualifying gap (the fixture's 10:15–13:00 gap), sized ~90 min, not overflowing it.
  - Remaining Top-3 tasks are placed in order into the 10:15–13:00 and 14:00–18:00 gaps without overflowing; no block is placed before 09:00 or the first event.
  - The "Would write:" list is **unchanged** from the pre-Stage-11 briefing — i.e. the time-block section adds **zero** mutations, and there is **no** attempted calendar write anywhere.
- [ ] **Step 3: Fix composition until the expectations hold; commit**

```bash
git add -A && git commit -m "fix: time-block proposal composition against fixtures"
```

---

### Task 4: Live dry-run to `#test`

**Files:** none.

- [ ] **Step 1: Run the skill with `DRY_RUN=1`** (live calendar + tasks). Verify with Stanton:
  - The `⏱ Time-blocks` section reflects **today's real** gaps and real Top 3, with sensible placements (top-1 in the best early gap; nothing double-booked; `G –` events excluded from the gaps used).
  - On a day with no free gaps, the section is omitted (or names the unplaced tasks) — no invented gaps.
  - Nothing was written to any calendar (confirm no `create_event`/`update_event` was attempted) and the only writes are the usual capture-triage + Journal ones.
- [ ] **Step 2: Commit any fixes**

```bash
git add -A && git commit -m "fix: time-block proposal live dry-run adjustments"
```

---

### Task 5: ✋ CHECKPOINT — time-blocks verified, Phase 2 stages complete

**Files:** none.

- [ ] **Step 1: After a real scheduled morning run** (or a manual production run): Stanton confirms the `⏱ Time-blocks` section is useful and accurate, and that no calendar event was ever created or changed.
- [ ] **Step 2: STOP.** Tell Stanton this closes the planned Phase 2 stages (6–11). Remaining committed-but-unplanned work: **Phase 2 item 7 — 121 action-point ingestion** (a future Stage 12, which reuses Stage 9's extraction convention) and **item 8 — Siri capture** (already live, phone-side only). Ask whether to plan Stage 12 next or pause.
- [ ] **Step 3: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 11 — time-block proposals live (suggestions only)" --allow-empty
```

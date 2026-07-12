# Stage 10 — Recurring Tasks Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** A Task can carry a natural-language `Recurrence` rule (e.g. "every Sunday"); when the evening run reconciles that task as completed, it spawns the next instance with the correct next due date — deduped so a rerun never double-spawns.

**Architecture:** No new skill. A new `Recurrence` (text) property on the Tasks database; a bounded, explicit recurrence grammar documented in `CLAUDE.md`; a spawn step added to the evening-shutdown reconcile phase. Spawns write via `scripts/notion.sh create` and dedupe on a `recur:{parent-page-id}:{next-due}` Source ID. Date math is Europe/London, computed by the run (not parsed from prose).

**Tech Stack:** `CLAUDE.md` task schema + rules, `scripts/notion.sh` (create/query), evening-shutdown skill, Notion.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md` (Phase 2 item 5). Reality contradicts it → STOP and ask Stanton; record with a dated note.
- Secrets only in cloud env vars + local shell.
- Notion writes only inside Second Brain (Tasks); all writes via `scripts/notion.sh` REST. `Habit Tracker`/`DND` never read; `CSD EL` read-only.
- All date logic explicitly Europe/London; relative dates resolve deterministically per the grammar — **never guess** an unparseable rule.
- Idempotency: spawning is deduped on the child's Source ID; a rerun or reprocess must never create a second next-instance.
- Anything only Stanton can do (add the property; mark a task done) is a **USER-ACTION** with exact instructions, then STOP.
- ✋ **CHECKPOINT:** a real recurring task, completed, spawns exactly one correct next instance (and none on rerun), then STOP for Stanton's confirmation before Stage 11.
- Commit after each task.

**Prerequisite:** Core complete (Stages 0–5); Phase 2 planning gate open; evening-shutdown reconcile step live. **Execution waits for Stanton's explicit go and the reliability bar.**

---

### Task 1: Add the `Recurrence` property to the Tasks database

**Files:**
- Modify: `CLAUDE.md` (Task schema table)

- [ ] **Step 1: USER ACTION — Stanton adds a text property to the Tasks database.** In Notion → Tasks database → **+ New property** → name `Recurrence`, type **Text**. **STOP and wait for confirmation.** (Adding a property in the UI is safest; the connector's schema-update tool is not relied on.)
- [ ] **Step 2: Verify the property exists** — `./scripts/notion.sh query 01e1c068-5703-423a-b910-f4bd5644e4ab | jq '.[0].properties | keys' | grep -i recurrence` returns `Recurrence` (query one task and confirm the property is present).
- [ ] **Step 3: Add the property to the `CLAUDE.md` Task schema table** (after `Source ID`):

```markdown
| Recurrence | text | natural-language rule (e.g. "every Sunday"); the evening run spawns the next instance when a recurring task is completed — see Recurrence rules |
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: Tasks Recurrence property (Stage 10) — in schema"
```

---

### Task 2: Recurrence grammar + evening spawn behaviour

**Files:**
- Modify: `CLAUDE.md` (new `### Recurrence rules` subsection under Task schema)
- Modify: `.claude/skills/evening-shutdown/SKILL.md` (new spawn step in reconcile)

**Interfaces:**
- Consumes: the `Recurrence` property from Task 1; `scripts/notion.sh create`/`query`; the "Done today" set computed by the evening reconcile step.
- Produces: the spawn behaviour + the `recur:{parent-page-id}:{next-due}` dedupe convention.

- [ ] **Step 1: Add a `### Recurrence rules` subsection to `CLAUDE.md`** immediately after the `### Aging rules` subsection:

```markdown
### Recurrence rules

A Task's `Recurrence` (text) holds a natural-language rule. When the evening run marks a
recurring task Done, it spawns the next instance. Supported rules (case-insensitive):

- `every day` / `daily` → +1 day
- `every weekday` → next Mon–Fri
- `every <weekday>` (e.g. `every Sunday`) → the next occurrence of that weekday
- `weekly` / `every week` / `every N weeks` → +7×N days
- `every N days` → +N days
- `monthly` / `every month` / `every N months` → same day-of-month N months on (clamp to
  the month's last day if it's shorter)

**Base date** = the completed task's Due if set, else the completion date. **Next Due** =
the first occurrence strictly after the base per the rule, in Europe/London. The new
instance copies Name, Domain, Priority, Project/Area, and Recurrence; Status `Next`;
Source = `Recurrence of {name}`; Source ID = `recur:{parent-page-id}:{next-due}`. An
**unparseable** rule is never guessed — leave the task Done, spawn nothing, and surface
`couldn't parse recurrence "{rule}" on {task}` in the evening DM's decisions-needed.
```

- [ ] **Step 2: Add a spawn step to `.claude/skills/evening-shutdown/SKILL.md`** immediately after the `Reconcile completions` step (renumber the following steps — Honest rollover, Decisions needed, Tomorrow preview, Compose/deliver/journal, and the Stage-7 dead-man's-switch ping — so numbering stays sequential):

```markdown
3. **Spawn recurring next instances.** For each task in today's "Done today" set with a
   non-empty `Recurrence`: compute the next Due per `CLAUDE.md → Recurrence rules` (base =
   the task's Due if set, else TODAY). Before creating, `scripts/notion.sh query` the
   Tasks DB by Source ID `recur:{parent-page-id}:{next-due}` — if a row exists, skip
   (rerun guard). Otherwise `scripts/notion.sh create` a new Task copying
   Name/Domain/Priority/Project-Area/Recurrence, Status `Next`, Due = next-due, Source =
   `Recurrence of {name}`, Source ID = `recur:{parent-page-id}:{next-due}`, Last Touched =
   TODAY. Never modify the completed task. An unparseable rule spawns nothing and goes to
   decisions-needed. Report spawned instances in the DM (e.g. "🔁 Water the plants → next
   Sun 19 Jul").
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md .claude/skills/evening-shutdown/SKILL.md
git commit -m "feat: recurrence grammar + evening spawn of next instance"
```

---

### Task 3: Dry walkthrough (the fixture rung)

**Files:**
- Create: `tests/fixtures/notion/tasks-recurring.json`

- [ ] **Step 1: Write `tests/fixtures/notion/tasks-recurring.json`**:

```json
[
  { "id": "rec-1", "name": "Water the plants", "status": "Done", "completed": "2026-07-12",
    "due": "2026-07-12", "recurrence": "every Sunday", "domain": "Personal", "priority": "Low" },
  { "id": "rec-2", "name": "Submit timesheet", "status": "Done", "completed": "2026-07-10",
    "due": "2026-07-10", "recurrence": "every weekday", "domain": "Work", "priority": "Medium" },
  { "id": "rec-3", "name": "Odd cadence", "status": "Done", "completed": "2026-07-12",
    "recurrence": "every second Tuesdayish" }
]
```

- [ ] **Step 2: Walk each row through the Recurrence rules by hand and print (do not run) the `scripts/notion.sh` calls.** Confirm with Stanton:
  - `rec-1` (`every Sunday`, base Sun 2026-07-12) → one `create`: Due **2026-07-19**, Status Next, Source ID `recur:rec-1:2026-07-19`, copies Personal/Low.
  - `rec-2` (`every weekday`, base Fri 2026-07-10) → one `create`: Due **2026-07-13** (Mon), Source ID `recur:rec-2:2026-07-13`.
  - `rec-3` (`every second Tuesdayish`) → **no create**; a decisions-needed line `couldn't parse recurrence "every second Tuesdayish" on Odd cadence`.
  - Re-walking with those child Source IDs already present → zero creates (dedupe).
- [ ] **Step 3: Add the fixture to `tests/fixtures/README.md`** as a standalone row:

```markdown
| Recurrence spawn check (Stage 10) | `notion/tasks-recurring.json` |
```

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/notion/tasks-recurring.json tests/fixtures/README.md
git commit -m "test: recurring-task fixture + expected next-instance math"
```

---

### Task 4: Live dry-run with a real recurring task

**Files:** none.

- [ ] **Step 1: USER ACTION — Stanton creates a recurring task and completes it.** In Notion (or via capture): a Task with a clear `Recurrence` (e.g. `every Sunday`) and a Due, then mark it **Done** (or send a `done:` capture for it). **STOP and wait.**
- [ ] **Step 2: Run the evening-shutdown skill with `DRY_RUN=1`.** Verify with Stanton (evidence):
  - Exactly **one** new Task was created: same Name, correct next Due per the rule, Status `Next`, Source ID `recur:{parent}:{next-due}` — show the Notion row.
  - The completed task is unchanged (still Done, same Due).
  - The `#test` DM lists the spawn ("🔁 {task} → next {date}").
  - An unparseable recurrence (if tested) produced a decisions-needed line and **no** new task.
- [ ] **Step 3: Idempotency proof — re-run `DRY_RUN=1` immediately.** Expected: **no** second instance (the `recur:` Source ID dedupe holds), and the completed parent is not re-processed (its Completed is already set).
- [ ] **Step 4: Commit any rule fixes**

```bash
git add -A && git commit -m "fix: recurring-task spawn live dry-run adjustments"
```

---

### Task 5: ✋ CHECKPOINT — recurrence verified

**Files:** none.

- [ ] **Step 1: Confirm with Stanton** the next instance appears with the right cadence and doesn't duplicate across reruns, and that non-recurring tasks are entirely unaffected.
- [ ] **Step 2: STOP.** Ask explicitly: "Recurring tasks spawn correctly and only once — happy to close Stage 10? Stage 11 (time-block proposals) starts only on your word." Wait.
- [ ] **Step 3: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 10 — recurring tasks spawn next instance" --allow-empty
```

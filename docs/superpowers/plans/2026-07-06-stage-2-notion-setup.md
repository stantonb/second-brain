# Stage 2 — Notion Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** The "Second Brain" Notion section exists with all five structures (Tasks, Journal, Capture Log, Reading list, Brag doc), exact properties, the rolling-list view, IDs recorded in `CLAUDE.md`, proven by a round-tripped test task.

**Architecture:** Stanton creates the one thing the Notion API cannot (a top-level page); everything under it is created via the Notion connector tools in-session. Views also cannot be created via the API, so they are exact-click user-action steps. All writes in this stage happen strictly inside the new Second Brain page.

**Tech Stack:** Notion connector (MCP tools in-session), Notion property types.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md`. Reality contradicts it (e.g. connector cannot create databases) → STOP and ask Stanton; record the agreed change in the spec with a dated note.
- **Writes in this stage go ONLY inside the new "Second Brain" page.** Never read/write `Habit Tracker`/`DND`; `CSD EL` read-only; nothing else in the workspace is touched.
- Database IDs are non-sensitive and DO go into `CLAUDE.md` (spec allows this); secrets never do.
- All date logic explicitly Europe/London.
- User-action steps: exact instructions, then STOP for Stanton's confirmation.
- Stage ends with verification showing real output (the round-trip).
- Commit after each task.

**Prerequisite:** Stage 1 complete (`CLAUDE.md` exists with the workspace map awaiting the `*(Stage 2)*` IDs; Notion tools available in-session).

---

### Task 1: USER ACTION — create the top-level "Second Brain" page

**Files:** none (Notion UI).

The public Notion API cannot create workspace-level pages, so this one page is Stanton's; everything beneath it is automated.

- [ ] **Step 1: Ask Stanton to do exactly this, then STOP and wait:**
  1. In Notion's left sidebar, next to **Private** (or **Workspace**, his choice — spec says alongside, not inside, the existing structure), click **+** to add a page.
  2. Title it exactly `Second Brain`. No icon/content needed.
  3. Click **Share → Copy link** and paste the link into chat (page links are non-sensitive).
  4. If the claude.ai Notion connector was granted per-page access in Stage 0, also add `Second Brain` to the granted pages (Notion → Settings → Connections → the Claude connection → Access selected pages → add it). Same for the local Notion MCP connection if separate.

- [ ] **Step 2: Extract the page ID from the link** (the 32-hex-char tail of the URL, formatted as 8-4-4-4-12) and verify the connector can see it: fetch the page by ID via the Notion tools. Expected: title `Second Brain`, empty children.

---

### Task 2: Create the Tasks database

**Files:** none (Notion writes via connector).

**Interfaces:**
- Produces: Tasks DB with the 17 properties below — names must match `CLAUDE.md → ## Task schema` exactly (skills query by these names).

- [ ] **Step 1: Via the Notion connector, create a database titled `Tasks`** as a child of the Second Brain page, with exactly these properties:

| Property | Type | Options (exact strings, in order) |
|---|---|---|
| Name | title | |
| Status | select | `Inbox`, `Next`, `In progress`, `Waiting`, `Done`, `Dropped` |
| Domain | select | `Work`, `Personal` |
| Project/Area | select | (no preset options) |
| Due | date | |
| Priority | select | `High`, `Medium`, `Low` |
| Created | created_time | |
| Completed | date | |
| Waiting-on | rich_text | |
| Blocked Reason | rich_text | |
| Snoozed Until | date | |
| Pinned | checkbox | |
| Rollover Count | number | |
| Last Rolled Over | date | |
| Last Touched | date | |
| Source | rich_text | |
| Source ID | rich_text | |

- [ ] **Step 2: Verify by fetching the database schema back** and diffing property names/types against the table above. Expected: all 17 present, correct types, correct select options.

---

### Task 3: Create the Journal, Capture Log, and Reading list databases

**Files:** none (Notion writes via connector).

**Interfaces:**
- Produces: three databases; property names below are load-bearing for the skills.

- [ ] **Step 1: Create `Journal`** (child of Second Brain):

| Property | Type | Options |
|---|---|---|
| Name | title | (holds the run ID, e.g. `morning-2026-07-06`) |
| Date | date | |
| Type | select | `Morning`, `Evening`, `Weekly` |

Body of each Journal page = full text of what was sent (written by the skills).

- [ ] **Step 2: Create `Capture Log`** (child of Second Brain):

| Property | Type | Options |
|---|---|---|
| Message ID | title | Discord message ID — the dedupe key |
| Raw Text | rich_text | |
| Processed At | date | |
| Outcome | select | `Task created`, `Reading list`, `Note`, `Status update`, `Needs Review`, `Skipped` |
| Confidence | select | `High`, `Medium`, `Low` |
| Link | url | Notion URL of the created/updated Task or Journal page |

- [ ] **Step 3: Create `Reading list`** (child of Second Brain):

| Property | Type | Options |
|---|---|---|
| Name | title | |
| URL | url | |
| Status | select | `Unread`, `Read` |
| Added | created_time | |

- [ ] **Step 4: Verify all three schemas by fetching them back** (as Task 2 Step 2). Expected: exact match.

---

### Task 4: Create the Brag doc page

**Files:** none (Notion writes via connector).

- [ ] **Step 1: Create a page titled `Brag doc`** as a child of Second Brain, with initial content:

```markdown
# Brag doc

Work wins, appended by the weekly review, grouped by month. Newest month first.

## July 2026
```

- [ ] **Step 2: Verify by fetching the page** — title and the `## July 2026` heading present.

---

### Task 5: USER ACTION — the rolling-list view

**Files:** none (Notion UI — views cannot be created via the API).

- [ ] **Step 1: Ask Stanton to do exactly this in the Tasks database, then STOP and wait:**
  1. Open **Tasks** as a full page. Click **+** next to the view tabs → **Table** → name it `Rolling list`.
  2. **Filter** → **+ Add advanced filter**:
     - `Status` **is any of** `Next`, `In progress`, `Waiting`
     - **AND** add a filter group: `Snoozed Until` **is empty** **OR** `Snoozed Until` **is on or before** `Today`.
  3. **Sort**: `Priority` ascending (High first, since options are ordered High/Medium/Low), then `Due` ascending.
  4. Optional but useful: a second view `Inbox` (Table, filter `Status is Inbox`) for eyeballing triage results.

- [ ] **Step 2: On confirmation, note the view exists.** (The skills compute the rolling list from properties — the view is for Stanton's eyes; no ID needed.)

---

### Task 6: Record IDs in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (the `## Notion workspace map` table)

**Interfaces:**
- Consumes: IDs from Tasks 1–4.
- Produces: complete workspace map — every skill resolves databases by these IDs, never by search.

- [ ] **Step 1: Replace the six `*(Stage 2)*` cells** in the workspace-map table with the real IDs (Second Brain page, Tasks, Journal, Capture Log, Reading list, Brag doc).

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: record Second Brain Notion database IDs in workspace map"
```

---

### Task 7: Round-trip verification (stage gate)

**Files:** none.

- [ ] **Step 1: CREATE** — via the connector, insert a Tasks row:
  - Name `Stage 2 smoke test`, Status `Inbox`, Domain `Personal`, Priority `Low`,
    Source `manual`, Source ID `manual-stage2-smoke`.
- [ ] **Step 2: READ BACK** — query Tasks for `Source ID = manual-stage2-smoke`; show Stanton the returned properties verbatim (evidence). Expected: one row, every property as written, Created auto-populated.
- [ ] **Step 3: UPDATE** — set Status `Done`, Completed = today (Europe/London), Last Touched = today. Read back; show the diff.
- [ ] **Step 4: DELETE** — archive the test row. Confirm a query for `manual-stage2-smoke` now returns nothing.
- [ ] **Step 5: Ask Stanton to eyeball the Second Brain section in Notion** (five structures + Rolling list view) and confirm. STOP and wait.
- [ ] **Step 6: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 2 — Notion Second Brain section live, round-trip verified" --allow-empty
```

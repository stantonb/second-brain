# Stage 6 — On-Demand Briefing ("Brief Me Now") Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** A "brief me now" on-demand path — the existing `morning-briefing` skill gains an on-demand mode (ad-hoc run ID, optional focus text, DM delivery, never clobbers the day's scheduled Journal page), triggered from an iOS Shortcut that POSTs to the morning-briefing routine's **fire** endpoint. No new infrastructure, no new skill.

**Architecture:** The `morning-briefing` skill already advertises "or an on-demand 'brief me'". Stage 6 makes that real in three parts: (1) a documented on-demand run contract in `CLAUDE.md` + the skill (on-demand signalled by `ON_DEMAND=1`/`BRIEF_FOCUS` locally or by run-context `text` injected by the fire endpoint in production; run ID `morning-{date}-ondemand-{HHMMSS}`; DM delivery; the scheduled `morning-{date}` page is never touched); (2) the fire endpoint on the existing routine + an iOS Shortcut that POSTs dictated focus text to it; (3) a one-line change so the weekly self-check ignores `-ondemand-*` pages just as it ignores `-test`.

**Tech Stack:** Claude Code `morning-briefing` skill, `scripts/discord.sh`, claude.ai routines fire endpoint (research preview), iOS Shortcuts.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md` (Phase 2 item 1 + the 2026-07-12 surface-verification note). Reality contradicts it → STOP and ask Stanton; record the agreed change with a dated note.
- Secrets only in cloud env vars + Stanton's local shell + (new) the iOS Shortcut's own storage. The per-routine fire **token is never pasted into chat, logs, or the repo** — it lives only on Stanton's phone.
- Notion writes only inside Second Brain; `Habit Tracker`/`DND` never read; `CSD EL` read-only.
- All date logic explicitly Europe/London (`TZ=Europe/London date`).
- Rule #1 — never fail silent: partial briefing + ⚠️ lines beats no briefing.
- **Idempotency:** on-demand runs get their own run ID and Journal page — they must never merge with, overwrite, or double-count against the scheduled `morning-{date}` page.
- Anything only Stanton can do on the personal claude.ai account (Routines UI, cloud env, iOS Shortcut) is a **USER-ACTION** with exact instructions, then STOP for confirmation.
- ✋ **CHECKPOINT:** a real on-demand fire delivers a DM without disturbing the scheduled morning run, then STOP for Stanton's confirmation before Stage 7.
- Commit after each task.

**Prerequisite:** Core complete (Stages 0–5); `morning-briefing` routine live at 06:45 Europe/London; Phase 2 planning gate open (spec note 2026-07-12). **Execution waits for Stanton's explicit go and the reliability bar (Sunday 19 Jul self-check clean or explained).**

---

### Task 1: USER-ACTION — verify the routine's real trigger surface & mint the fire token

**Files:** none (personal-account UI).

**Interfaces:**
- Produces: the confirmed fire-endpoint URL **shape** + required headers (e.g. `anthropic-beta`) reported back to this session; the per-routine bearer **token** held only on Stanton's phone. Consumed by Tasks 5–6.

- [ ] **Step 1: USER ACTION — Stanton, in a browser on your personal claude.ai account**, open **claude.ai/code/routines → `morning-briefing`**. Confirm and report back (paste the URL shape + headers, **NOT** the token value):
  1. A **"Run now"** button exists on the routine (manual trigger).
  2. Whether the routine exposes an **on-demand fire / API trigger** — an endpoint of roughly the shape `POST https://api.anthropic.com/v1/claude_code/routines/{routine_id}/fire` with a **per-routine bearer token** and an experimental `anthropic-beta` header, accepting an optional `{"text": "..."}` run-context body.
  3. Generate/copy the fire **token**. Store it **only** in a secure place you control (you will paste it into the iOS Shortcut in Task 5) — do **not** send it into this chat.
  Report: the exact fire URL, the exact `anthropic-beta` header value, and whether a `text` body is accepted. **STOP and wait.**
- [ ] **Step 2: Branch on reality.**
  - **If the fire endpoint exists** (expected, per the spec's 2026-07-12 verification note): proceed to Task 2. Record the confirmed URL shape + header verbatim in `docs/setup.md` §8 (written in Task 5) — never the token.
  - **If the UI shows only "Run now" and no external endpoint:** reality differs from the spec. **STOP.** Record a dated spec note ("2026-07-12+: routines expose only manual Run-now, no external fire endpoint — on-demand-from-phone deferred; 'brief me now' available via Run-now in the app only"), tell Stanton, and pause Stage 6 for his direction. Do not invent an endpoint.

---

### Task 2: On-demand run contract in CLAUDE.md + the morning-briefing skill

**Files:**
- Modify: `CLAUDE.md` (Run conventions: on-demand run ID + idempotency carve-out)
- Modify: `.claude/skills/morning-briefing/SKILL.md` (Modes table + Procedure step 0)

**Interfaces:**
- Consumes: the existing three-mode contract and the Morning format.
- Produces: the on-demand behaviour the fire endpoint and local dry-runs both drive: run ID `morning-$TODAY-ondemand-$(TZ=Europe/London date +%H%M%S)`, optional `$BRIEF_FOCUS`, DM delivery, scheduled page untouched.

- [ ] **Step 1: Edit `CLAUDE.md` → `## Run conventions`.** Add this bullet immediately after the existing **Run ID** bullet:

```markdown
- **On-demand ("brief me now"):** an on-demand morning briefing uses run ID
  `morning-{YYYY-MM-DD}-ondemand-{HHMMSS}` (Europe/London). It is **never**
  idempotency-merged with the scheduled `morning-{YYYY-MM-DD}` page — each brief-me is
  its own Journal entry, delivered as a DM. On-demand is signalled by `ON_DEMAND=1`
  (with optional `BRIEF_FOCUS` text) for local runs, or by run-context text injected by
  the routine's fire endpoint in production. On-demand pages (`-ondemand-*`) and `-test`
  pages are excluded from the weekly 14-entry self-check.
```

- [ ] **Step 2: Edit `.claude/skills/morning-briefing/SKILL.md` → the `## Modes` table.** Add one row after the `(neither)` production row:

```markdown
| `ON_DEMAND=1` (+ optional `BRIEF_FOCUS="..."`) | On-demand "brief me now": run ID `morning-$TODAY-ondemand-$(TZ=Europe/London date +%H%M%S)`, DM delivery, **never touch the scheduled `morning-$TODAY` page**. If `BRIEF_FOCUS` is set, weave it into ordering/emphasis and note it in the header. In production this same mode is triggered by run-context text injected via the routine's fire endpoint (treat that text as `BRIEF_FOCUS`); with no injected text a routine run is the normal scheduled briefing. Combine with `DRY_RUN=1` to deliver an on-demand test to `#test`. |
```

- [ ] **Step 3: Edit `.claude/skills/morning-briefing/SKILL.md` → Procedure step 0 (`Dates & idempotency`).** Replace it with:

```markdown
0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)`.
   - **Scheduled/normal run** (no `ON_DEMAND`, no injected run-context text): run ID
     `morning-$TODAY` (plus `-test` in DRY_RUN). Query the Journal database (ID in
     CLAUDE.md) for a page titled with the run ID: if it exists this is a rerun — update
     that page and note "(rerun)"; never create a duplicate.
   - **On-demand run** (`ON_DEMAND=1`, or run-context text was injected by the fire
     endpoint): run ID `morning-$TODAY-ondemand-$(TZ=Europe/London date +%H%M%S)` (plus
     `-test` in DRY_RUN). This is always a fresh page — do **not** look up or update the
     scheduled `morning-$TODAY` page. Treat any injected run-context text (or
     `$BRIEF_FOCUS`) as focus: bias the Top-3 ordering and emphasis toward it and add a
     one-line "🎯 On-demand brief — focus: {text}" under the header. Deliver as a DM
     (or to `#test` under DRY_RUN) exactly like the scheduled run.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md .claude/skills/morning-briefing/SKILL.md
git commit -m "feat: on-demand 'brief me now' run contract (ad-hoc run ID, focus text)"
```

---

### Task 3: Weekly self-check ignores on-demand pages

**Files:**
- Modify: `.claude/skills/weekly-review/SKILL.md` (self-check step 4)

**Interfaces:**
- Consumes: the run-ID convention from Task 2.
- Produces: an honest 14-count that isn't inflated by on-demand briefs.

- [ ] **Step 1: Edit `.claude/skills/weekly-review/SKILL.md` → Procedure step 4 (`Self-check`).** Change the parenthetical `(14 total; ignore \`-test\` pages)` to `(14 total; ignore \`-test\` and \`-ondemand-*\` pages)`. The exact replacement:

```markdown
4. **Self-check.** Expected Journal entries for the week = `morning-` and `evening-`
   for each of the 7 days (14 total; ignore `-test` and `-ondemand-*` pages). Report
   `{N}/14` and list every missing run ID with ⚠️. A green routine status only means the
   session ran — this check is what catches quiet failures.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/weekly-review/SKILL.md
git commit -m "fix: weekly self-check ignores on-demand brief pages"
```

---

### Task 4: Fixture-mode verification of on-demand composition

**Files:** none (reuses existing fixtures).

- [ ] **Step 1: In this session, run the morning-briefing skill with `FIXTURE_MODE=1 ON_DEMAND=1 BRIEF_FOCUS="focus on this evening"`.**
- [ ] **Step 2: Verify against these expectations (show Stanton the output):**
  - The run ID is `morning-<today>-ondemand-<HHMMSS>` — **not** `morning-<today>`.
  - The header carries the "🎯 On-demand brief — focus: focus on this evening" line, and the Top-3 ordering/emphasis visibly reflects the focus (e.g. evening-relevant items surfaced), while still drawing only on the fixture data.
  - The "Would write:" list targets the **on-demand** Journal page and does **not** mention updating `morning-<today>` — the scheduled page is left alone.
  - Capture triage, calendar, rolling list, email, GitHub sections are otherwise identical to the scheduled fixture briefing (same fixtures → same content).
- [ ] **Step 3: Run once more with `FIXTURE_MODE=1 ON_DEMAND=1` and no `BRIEF_FOCUS`** — verify it composes a normal briefing on an on-demand page with no focus line and no error.
- [ ] **Step 4: Fix any composition bugs and re-run until the expectations hold; commit**

```bash
git add -A && git commit -m "fix: on-demand briefing composition against fixtures"
```

---

### Task 5: Live on-demand dry-run + build the iOS Shortcut

**Files:**
- Modify: `docs/setup.md` (new `## 8. On-demand "brief me now" (iOS Shortcut)`)

> **2026-07-13 (dated note — execution):** Step 1's live `#test` dry-run is **deferred to
> the personal-cloud environment** at Stanton's direction. The local CLI session runs on
> the WORK Claude account, which cannot reach Google (Calendar MCP token expired, Gmail
> connector absent from the session), so a local `DRY_RUN` would `⚠️` both the Calendar
> and Email sections — a work-account environment limit, **not** a Stage 6 defect.
> Tasks 2–4 are done and committed on this branch (`0fe5b5c`, `3b545a8`); the fixture run
> proved the on-demand mechanics (ad-hoc run ID `morning-<date>-ondemand-<HHMMSS>`,
> scheduled page never looked up/touched, focus line + biased Top-3, `#test`/DM delivery).
> Before-state of today's scheduled page locked for the eventual idempotency proof:
> `morning-2026-07-13` id `39cedd10-0411-81d2-9810-e82339954695`,
> `last_edited_time 2026-07-13T05:52:00.000Z`. Step 1 now runs on the personal cloud in
> the production window (with Task 1 + Steps 2–5), gated on the reliability bar
> (Sunday 19 Jul self-check clean/explained) + Stanton's explicit go.

- [ ] **Step 1: Run the skill with `DRY_RUN=1 ON_DEMAND=1 BRIEF_FOCUS="test brief"`** (secrets sourced): live reads, real capture triage (idempotent), delivery to `#test`. Verify with Stanton (evidence, not claims):
  - `#test` receives an on-demand briefing with the focus line.
  - Journal page `morning-<today>-ondemand-<HHMMSS>-test` exists with the full text.
  - The scheduled `morning-<today>` page (if today's 06:45 run already created one) is **unchanged** — show its `last_edited_time` before/after.
- [ ] **Step 2: Write `docs/setup.md` §8** with exactly this content (fill the URL/header from Task 1's confirmed values; never the token):

````markdown
## 8. On-demand "brief me now" (iOS Shortcut)

Triggers the `morning-briefing` routine ad-hoc from your phone. Uses the routine's fire
endpoint (confirmed in the Routines UI, Stage 6 Task 1). The fire **token** is a secret —
it lives only in this Shortcut.

1. claude.ai/code/routines → `morning-briefing` → copy the **fire URL** and generate a
   **token** (shown once). Note the required `anthropic-beta` header value.
2. iPhone → **Shortcuts** → **+**, name it `Brief me`:
   - **Ask for Input** (Text, prompt "Focus? (optional)") — dictated via Siri.
   - **Get Contents of URL** → paste the fire URL → Method **POST** →
     **Headers:** `Authorization` = `Bearer <token>`, `anthropic-beta` = `<value from step 1>`,
     `Content-Type` = `application/json` →
     Request Body **JSON** → field `text` = *Provided Input*.
3. Say "Hey Siri, Brief me", optionally dictate a focus, done. A DM arrives with the
   briefing; a `morning-<date>-ondemand-<HHMMSS>` Journal page is written. The scheduled
   06:45 run is untouched. Manual test fires from the UI's **Run now** button don't count
   against the routine quota; API fires do.
````

- [ ] **Step 3: USER ACTION — Stanton builds the Shortcut** per §8, pasting the real fire URL + token (token phone-side only). **STOP and wait.**
- [ ] **Step 4: USER ACTION — Stanton fires it once** ("Hey Siri, Brief me", focus "top 3 only"). Verify together: a real DM arrives; a `morning-<today>-ondemand-<HHMMSS>` Journal page exists with the focus reflected; no scheduled-page disruption. **STOP and wait.**
- [ ] **Step 5: Commit**

```bash
git add docs/setup.md
git commit -m "docs: setup §8 — on-demand brief-me iOS Shortcut (fire endpoint)"
```

---

### Task 6: ✋ CHECKPOINT — on-demand verified, scheduled run undisturbed

**Files:** none.

- [ ] **Step 1:** Confirm with Stanton that a phone-fired "brief me now" delivers a correct DM within a minute or two, and that the next scheduled 06:45 run still produces its own separate `morning-<date>` page (no collision, no double-count in the weekly self-check).
- [ ] **Step 2: STOP.** Ask Stanton explicitly: "On-demand briefing works and doesn't disturb the scheduled run — happy to close Stage 6? Stage 7 (dead-man's switch) starts only on your word." Wait for confirmation.
- [ ] **Step 3: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 6 — on-demand 'brief me now' live, scheduled run undisturbed" --allow-empty
```

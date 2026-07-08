# Stage 3 — Morning Briefing Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** A `morning-briefing` skill proven against fixtures, then live against `#test`, then running as a real 06:45 Europe/London routine with **two consecutive real morning DM deliveries** confirmed by Stanton.

**Architecture:** The skill (`.claude/skills/morning-briefing/SKILL.md`) implements the spec's 8-step morning procedure, delegating all constants to `CLAUDE.md` and all Discord I/O to `scripts/discord.sh`. Three modes: `FIXTURE_MODE=1` (canned data, no network/writes), `DRY_RUN=1` (live reads, delivery to `#test`, `-test` run ID), production (DM + Journal). The routine is a claude.ai cloud schedule cloning this repo.

**Tech Stack:** Claude Code skill, Notion/Gmail/Google Calendar connectors, `gh`, `scripts/discord.sh`, claude.ai routines.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md`. Reality contradicts it (routine surface differs, connector missing in cloud runs) → STOP and ask Stanton; record the agreed change with a dated note.
- Secrets only in the cloud environment's env vars + Stanton's local shell. Never committed/echoed.
- Notion writes only inside Second Brain; `Habit Tracker`/`DND` never read; `CSD EL` read-only.
- All date logic explicitly Europe/London (`TZ=Europe/London date +%F`).
- GitHub reads restricted to `CLAUDE.md → ## GitHub repo allowlist`.
- Rule #1 — never fail silent: partial briefing + ⚠️ lines beats no briefing; Discord down → Journal still written.
- User-action steps: exact instructions, then STOP for confirmation.
- ✋ **CHECKPOINT:** after two consecutive real deliveries, STOP and wait for Stanton to confirm the briefings look right before Stage 4 begins.
- Commit after each task.

**Prerequisite:** Stages 0–2 complete (env verified, `discord.sh` tested, Notion databases live with IDs in `CLAUDE.md`).

---

### Task 1: Google fixtures

**Files:**
- Create: `tests/fixtures/google/calendar-today.json`
- Create: `tests/fixtures/google/gmail.json`

**Interfaces:**
- Produces: fixture shapes for the skills' calendar/email sections (already listed in `tests/fixtures/README.md`'s mapping table).

- [ ] **Step 1: Write `tests/fixtures/google/calendar-today.json`**

```json
{
  "events": [
    { "start": "09:30", "end": "10:15", "title": "CSD standup", "calendar": "work" },
    { "start": "13:00", "end": "14:00", "title": "1:1 — Priya", "calendar": "work" },
    { "start": "19:00", "end": "20:30", "title": "Five-a-side", "calendar": "personal" }
  ]
}
```

- [ ] **Step 2: Write `tests/fixtures/google/gmail.json`**

```json
{
  "needs_reply": [
    { "from": "Maya Chen", "subject": "Q3 platform review — your slides?", "received": "yesterday" }
  ],
  "deadlines": [
    { "source": "HMRC reminder", "deadline": "2026-07-31", "what": "self-assessment payment on account" }
  ],
  "waiting_on": [
    { "to": "Alex Kim", "subject": "Contract renewal next steps", "sent_days_ago": 4 }
  ]
}
```

- [ ] **Step 3: Verify parse and commit**

```bash
jq -e . tests/fixtures/google/calendar-today.json tests/fixtures/google/gmail.json > /dev/null && echo OK
git add tests/fixtures/google
git commit -m "test: add Google calendar/gmail fixtures for briefing dry-runs"
```

---

### Task 2: The `morning-briefing` skill

**Files:**
- Create: `.claude/skills/morning-briefing/SKILL.md`

**Interfaces:**
- Consumes: `CLAUDE.md` (workspace map IDs, triage rules, Morning format, allowlist, timezone rule), `scripts/discord.sh` (`fetch-captures`, `react`, `send-dm`, `send-channel`), fixtures.
- Produces: the run procedure the routine invokes. The mode contract (`FIXTURE_MODE`, `DRY_RUN`) is reused verbatim by Stages 4–5.

- [ ] **Step 1: Write `.claude/skills/morning-briefing/SKILL.md` with exactly this content**

````markdown
---
name: morning-briefing
description: Compose and deliver the ~7am morning briefing DM — capture triage, today's calendar, top-3 tasks, email triage, GitHub PRs/CI, aging flags, decisions needed. Use for the daily 06:45 routine or an on-demand "brief me".
---

# Morning briefing

Read `CLAUDE.md` in full first — identity, workspace map (with hard exclusions), triage
rules, the Morning format, the GitHub repo allowlist, and the Europe/London rule all bind
this run. Rule #1: never fail silent.

## Modes

| Env | Effect |
|---|---|
| `FIXTURE_MODE=1` | Read `tests/fixtures/**` per the mapping in `tests/fixtures/README.md` instead of live services. No network, **no Notion writes, no Discord sends** — print the composed briefing to stdout plus a "Would write:" list of every mutation that production would have made. |
| `DRY_RUN=1` | Live reads and real capture triage (it is idempotent), but delivery goes to `#test` via `./scripts/discord.sh send-channel "$DISCORD_TEST_CHANNEL_ID"` and the run ID gets a `-test` suffix. |
| (neither) | Production: DM via `send-dm`, Journal under the plain run ID. |

## Procedure

0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)`. Run ID
   `morning-$TODAY` (plus `-test` in DRY_RUN). Query the Journal database (ID in
   CLAUDE.md) for a page titled with the run ID: if it exists this is a rerun — update
   that page and note "(rerun)"; never create a duplicate.
1. **Triage captures.**
   - Cursor = the highest Message ID across Capture Log rows (`0` if none).
   - `./scripts/discord.sh fetch-captures "$DISCORD_CAPTURE_CHANNEL_ID" "$CURSOR"`
   - Skip messages already in the Capture Log (Message ID match) and messages authored
     by the bot.
   - Apply CLAUDE.md's triage intent rules to each remaining message. Per message, in
     this order: make the Notion mutation → write the Capture Log row (Message ID,
     Raw Text, Processed At = now, Outcome, Confidence, Link) →
     `./scripts/discord.sh react "$DISCORD_CAPTURE_CHANNEL_ID" "$MSG_ID"`.
     Low-confidence `done:`/`drop:` matches → Outcome `Needs Review`, no guessing.
2. **Calendar.** Today's events from every connected Google Calendar (personal account;
   plus the shared work calendar if that fallback is live). List chronologically with
   times; note gaps ≥ 45 min between 09:00–18:00. For work meetings, context may be
   pulled from `CSD EL` sub-pages — **read-only** — when a one-liner would help.
3. **Tasks.** Query the Tasks DB for the rolling list (Status `Next`/`In progress`/
   `Waiting`, Snoozed Until empty or ≤ today). Pick the **top 3** by: overdue/due-today
   first, then Priority (High→Low), then age (oldest first). Everything else gets one
   line each.
4. **Email.** From Gmail: inbox messages that need a reply; explicit deadlines spotted;
   waiting-on = my sent mail from the last 7 days with no reply on the thread.
5. **GitHub.** For each repo in CLAUDE.md's allowlist ONLY:
   - `gh pr list --repo "$REPO" --search "review-requested:@me" --state open --json number,title,url`
   - `gh pr list --repo "$REPO" --author "@me" --state open --json number,title,url,reviewDecision,statusCheckRollup`
   - CI failed overnight = my open PRs with any `statusCheckRollup` conclusion `FAILURE`.
6. **Aging flags.** Rolling-list tasks (unpinned, unsnoozed, Status `Next`/`In progress`)
   whose age (days since Last Touched, falling back to Created) > 14 → ⏳ with age.
7. **Decisions needed.** Capture Log rows with Outcome `Needs Review` that are still
   unresolved, plus anything else awaiting Stanton's call.
8. **Compose, deliver, journal.**
   - Compose exactly per `CLAUDE.md → ## Briefing formats → Morning`. Omit empty
     sections. One ⚠️ line at the bottom per unreachable service.
   - Deliver per mode (stdin pipe into `discord.sh`).
   - Write the full delivered text to the Journal page (title = run ID, Date = TODAY,
     Type = `Morning`) — **even if Discord delivery failed**.

## Never

- Write to Notion outside the Second Brain section; read Habit Tracker or DND.
- Skip delivery because one service failed (rule #1 — send what succeeded, flag the rest).
- Add a ✅ reaction before its Capture Log row exists.
- Read GitHub repos outside the allowlist.
````

- [ ] **Step 2: Commit**

```bash
git add .claude/skills/morning-briefing/SKILL.md
git commit -m "feat: morning-briefing skill (fixture/dry-run/production modes)"
```

---

### Task 3: Fixture dry-run (no network)

**Files:** none.

- [ ] **Step 1: In this session, run the skill with `FIXTURE_MODE=1`** — compose the briefing purely from `tests/fixtures/**`.
- [ ] **Step 2: Verify the output against these expectations** (show Stanton the full text — evidence):
  - Captured line reports: 1 task (`waiting: Sam contract review…`), 1 link (`example.com/how-to-think-in-systems`), 1 needs-review (`done: expenses` — no matching task in `notion/tasks.json`).
  - Calendar shows the 3 fixture events and the 10:15–13:00 / 14:00–18:00 gaps (and does not invent a gap before 09:30).
  - Top 3 includes `Q3 roadmap draft` first (due 2026-07-06, High).
  - Rolling list marks `Chase legal re DPA` as `[W] … waiting on Sam`.
  - Aging flags ⏳ `Book dentist` (>14 days) and — because it is >14d too — `Write blog post on routines`; `Renew passport` is NOT flagged (pinned).
  - Email section shows Maya Chen reply, HMRC deadline, Alex Kim waiting-on (4d).
  - GitHub shows review-requested #4123, own PR #4098 with CI FAILURE.
  - Decisions needed contains the `done: expenses` capture.
  - A "Would write:" list itemises: 1 Task create, 1 Reading list create, 3 Capture Log rows, 1 Journal page — and zero writes outside Second Brain.
- [ ] **Step 3: Fix any composition bugs and re-run until the expectations hold** (systematic-debugging if anything is surprising). Commit fixes:

```bash
git add -A && git commit -m "fix: morning briefing composition against fixtures"
```

---

### Task 4: Live dry-run to `#test`

**Files:** none.

- [ ] **Step 1: Ask Stanton to drop 2–3 real test messages into `#capture`** (suggest: one URL, one `waiting: <person> <thing>`, one plain actionable sentence). STOP and wait.
- [ ] **Step 2: Run the skill with `DRY_RUN=1`** (secrets sourced): live Notion/Gmail/Calendar/GitHub reads, real capture triage, delivery to `#test`.
- [ ] **Step 3: Verify with Stanton (evidence, not claims):**
  - The briefing arrived in `#test`, formatted per the Morning template, real data.
  - Each test capture got a ✅ reaction, a Capture Log row, and the right Notion object (Task / Reading list row).
  - Journal page `morning-<today>-test` exists with the full text.
- [ ] **Step 4: Idempotency proof — run `DRY_RUN=1` again immediately.** Expected: no re-triage (Capture Log dedupe holds — capture counts say "nothing new"), the same `morning-<today>-test` Journal page updated, not duplicated, and no duplicate Tasks.
- [ ] **Step 5: Commit any fixes**

```bash
git add -A && git commit -m "fix: morning briefing live dry-run adjustments"
```

---

### Task 5: Create the routine (06:45 Europe/London)

**Files:** none (cloud config).

- [ ] **Step 1: Push the repo state the routine will clone** — ensure all Stage 0–3 commits are pushed to `main` (routines clone the remote, not this working copy).
- [ ] **Step 2: Create the schedule** — use the `schedule` skill (routines surface) to create routine `morning-briefing`: daily at 06:45, timezone **Europe/London**, repo = this repo, prompt:

```text
Read CLAUDE.md, then use the morning-briefing skill to compose and deliver today's
morning briefing. Production mode (no FIXTURE_MODE, no DRY_RUN). Rule #1: never fail
silent — partial briefing with ⚠️ lines beats no briefing.
```

If the routines surface differs from what the `schedule` skill expects (research preview), STOP and ask Stanton — do not improvise a different scheduler.

- [ ] **Step 3: USER ACTION — cloud environment config.** Ask Stanton, at claude.ai → Claude Code → this repo's environment/routine settings (per `docs/setup.md` §6):
  1. Environment variables: `DISCORD_BOT_TOKEN`, `DISCORD_USER_ID`, `DISCORD_CAPTURE_CHANNEL_ID`, `DISCORD_TEST_CHANNEL_ID`, `GH_TOKEN` (values from his local env file).
  2. Network access: **Custom** → default allowlist + `discord.com`.
  3. Connectors on the routine: **Notion, Gmail, Google Calendar only** — remove any others.
  STOP and wait for confirmation.
- [ ] **Step 4: Trigger one manual routine run now** (run-now on the schedule). Verify: DM arrives (Stanton confirms), Journal page `morning-<today>` exists (check via connector; note the earlier `-test` page is separate). If the run fails, read its logs and fix (systematic-debugging) before relying on the schedule.

---

### Task 6: ✋ CHECKPOINT — two consecutive real deliveries

**Files:** none.

> **2026-07-08:** Morning 1 (Wed 8 Jul) verified — Journal `morning-2026-07-08`
> created 06:49 BST, single page, correct format; capture invariants cross-checked
> (Capture Log rows + Tasks with matching Source IDs). Stanton explicitly waived
> Morning 2 (Thu 9 Jul) the same day ("Lets skip tomorrows briefing and continue") —
> checkpoint closed on **one** scheduled delivery at his call; Stage 4 unblocked.

- [ ] **Step 1: Morning 1** — after the first scheduled 06:45 run: Stanton confirms the DM (time ~07:00, content sane); check the Journal page exists and matches the DM.
- [ ] **Step 2: Morning 2** — same checks the next day. Two consecutive scheduled deliveries = the gate.
- [ ] **Step 3: STOP.** Ask Stanton explicitly: "Do the briefings look right — content, ordering, tone, timing? Stage 4 (evening shutdown) starts only on your word." Wait for confirmation.
- [ ] **Step 4: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 3 — morning briefing routine live, two real deliveries verified" --allow-empty
```

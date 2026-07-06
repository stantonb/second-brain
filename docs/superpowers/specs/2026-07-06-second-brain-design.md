# Second Brain — Design Spec

**Date:** 2026-07-06
**Status:** Approved pending user review
**Owner:** Stanton Borthwick

## Goal

A personal "second brain" built on Claude Code cloud routines that:

- Sends a **7am Discord DM** each morning: today's calendar, a rolling work+personal
  to-do list, email triage, a waiting-on list, and GitHub PR status.
- Sends a **9pm evening shutdown DM**: what got done, honest task rollover, tomorrow's shape.
- Sends a **Sunday weekly review DM**: wins, dropped balls, stale-task culls, and appends
  work wins to a brag doc.
- Accepts capture anytime via a private **Discord #capture channel**, triaged into Notion
  during the morning and evening runs.
- Uses **Notion** as the source of truth for tasks and memory, and **respects the existing
  Notion workspace structure** (see Data Model).

Zero self-hosted infrastructure: everything runs on Anthropic-managed cloud routines
(claude.ai/code/routines) against this repo.

## Non-goals (phase 1)

- Real-time two-way chat with the brain (requires an always-on bot; roadmap).
- Meeting-prep briefs N minutes before events (routines have a 1-hour minimum interval; roadmap).
- Anything touching the Notion **Habit Tracker** or **DND** structures — excluded entirely,
  read and write.

## Architecture

This repo (`second-brain`) is cloned by every routine run. It contains **behavior, not state**:

```
second-brain/
  CLAUDE.md                      # schema file: identity, Notion workspace map + DB schemas,
                                 # triage rules, briefing format, tone, exclusions
  .claude/skills/
    morning-briefing/SKILL.md
    evening-shutdown/SKILL.md
    weekly-review/SKILL.md
  scripts/
    discord.sh                   # send DM, fetch unprocessed capture messages, add ✅ reactions
  docs/
    setup.md                     # runbook: bot creation, tokens, connectors, routine config
    superpowers/specs/           # this spec
```

### Routines

| Routine | Schedule | Job |
|---|---|---|
| `morning-briefing` | Daily 06:45 Europe/London | Triage captures → compose + DM briefing → log to Journal |
| `evening-shutdown` | Daily 21:00 | Triage captures + status updates → rollover → DM shutdown → log |
| `weekly-review` | Sunday 17:00 | Week retro from Journal/Tasks/CSD EL → brag doc append → DM → log |

06:45 accounts for routine start stagger (a few minutes), landing the DM ~7am.

### Access per service (Approach A: hybrid)

| Service | Path | Notes |
|---|---|---|
| Notion | claude.ai Notion connector | First-class connector; works inside routines |
| Gmail/Calendar (personal) | claude.ai Google connectors | |
| Gmail/Calendar (work) | claude.ai Google connectors **if** Simply Business IT allows | Fallback: share work calendar into personal calendar; work email drops to roadmap |
| Discord | Bot token + REST via `curl` (`scripts/discord.sh`) | No hosted MCP dependency |
| GitHub | `gh` CLI with `GH_TOKEN` | PR status across repos |

### Cloud environment

- Network access: **Custom** — default allowlist **plus `discord.com`**.
- Environment variables (secrets, never in repo):
  - `DISCORD_BOT_TOKEN`
  - `DISCORD_USER_ID` (for opening the DM channel)
  - `DISCORD_CAPTURE_CHANNEL_ID`
  - `DISCORD_TEST_CHANNEL_ID` (dry-run target)
  - `GH_TOKEN`
- Connectors on the routines: Notion, Gmail, Google Calendar. Remove all others.

## Notion data model

### Existing workspace (mapped in CLAUDE.md, discovered precisely during implementation)

- **`CSD EL`** — the hub for all work notes; sub-pages beneath it are updated weekly.
  The brain treats this as a **read-mostly context source**:
  - The weekly review reads recently updated sub-pages under `CSD EL` for work wins
    (feeding the brag doc) and context on active workstreams.
  - The morning briefing may reference it for meeting context.
  - In phase 1 the brain **never writes** under `CSD EL` — no restructuring, renaming,
    or appending. Any write access there is a future phase's explicit decision.
- **`Habit Tracker`** — fully excluded. Never read, never written.
- **`DND`** — fully excluded. Never read, never written.
- Everything else: readable as context, but no writes outside the Second Brain section below.

An implementation task enumerates the real page/database IDs via the Notion connector and
records them (including exclusion IDs) in CLAUDE.md's workspace map.

### New: "Second Brain" top-level section

Created alongside (not inside) the existing structure:

- **Tasks** (database) — the rolling to-do list.
  - Name (title), Status (`Inbox / Next / In progress / Waiting / Done / Dropped`),
    Domain (`Work / Personal`), Due (date), Priority (`High / Medium / Low`),
    Created (created time), Completed (date), Waiting-on (text: person),
    Source (text: Discord message ID, email link, or `manual`).
  - The rolling list = view of `Next + In progress + Waiting`.
- **Journal** (database) — one page per run: Date, Type (`Morning / Evening / Weekly`),
  body = full text of what was sent. Memory for rollover honesty, the weekly self-check,
  and future pattern analysis.
- **Reading list** (database) — Name, URL, Status (`Unread / Read`), Added.
- **Brag doc** (page) — appended by the weekly review, grouped by month.

### Aging rules (in CLAUDE.md)

- Task in `Next`/`In progress` for **>14 days** → flagged in briefings with its age.
- **>30 days** → weekly review proposes moving it to `Dropped` (user confirms via capture reply).

## Discord design

- Private server ("Second Brain") containing the bot; channels `#capture` and `#test`.
- Briefings arrive as **DMs** from the bot (POST `/users/@me/channels` with
  `DISCORD_USER_ID`, then post; respect 2000-char limit by splitting).
- Bot needs the **Message Content privileged intent** (toggle in the dev portal) and
  read/send/reaction permissions.

### Capture protocol

- Each run fetches recent `#capture` messages and processes only those **without a ✅
  reaction from the bot**; it adds ✅ after processing. No timestamp bookkeeping; the user
  can see ingestion state at a glance.
- Triage intent rules (in CLAUDE.md):
  - URL → Reading list.
  - `done: <text>` / `drop: <text>` → fuzzy-match an existing Task, update Status.
  - Anything actionable → Task (infer Domain, Due, Priority; default Status `Inbox`,
    promoted to `Next` if clearly actionable).
  - Otherwise → appended as a note to today's Journal page.
- Every processed capture is confirmed in the next briefing/shutdown ("Captured: 3 tasks, 1 link").

## Run behavior

### Morning briefing (06:45)

1. Triage unprocessed captures.
2. Calendar: today's events across both accounts, gaps noted.
3. Tasks: pick **top 3** (due date, priority, aging), then the rest of the rolling list one line each.
4. Email: messages needing replies; deadlines spotted; **waiting-on** = sent mail from the
   last 7 days with no reply.
5. GitHub: PRs awaiting my review; my open PRs' status; CI failures overnight.
6. Aging flags (>14 days).
7. Compose in the CLAUDE.md format → DM → save full text to Journal.

### Evening shutdown (21:00)

1. Triage captures, including `done:`/`drop:` updates.
2. Reconcile: Tasks completed today (Notion status changes + capture messages).
3. **Honest rollover**: incomplete due-today items listed with rollover count
   ("X rolled over, 4th time") — computed from Journal history.
4. Tomorrow preview: first meeting, day shape.
5. DM → Journal.

### Weekly review (Sunday 17:00)

1. Read the week's Journal pages + Tasks activity + recently updated `CSD EL` sub-pages.
2. Compose: wins, dropped balls, stale-task cull proposals (>30 days), next week's shape.
3. Append work wins to the Brag doc (month section).
4. **Self-check**: scan Journal for the expected 14 daily entries; report any gaps
   (a silent-failure detector, since a green run status only means the session ran).
5. DM → Journal.

## Error handling

- **Never fail silent**: rule #1 in every skill — if an integration is unreachable, still
  send the DM with whatever succeeded plus an explicit "⚠️ couldn't reach <service>" line.
- A missing 7am DM is itself the alert; the weekly self-check catches quieter failures.
- If Discord itself is down, the run writes the briefing to Journal anyway (the DM is
  delivery, Notion is truth).
- Secrets only in cloud environment env vars. The repo is private; still, no IDs/tokens
  committed beyond non-sensitive database IDs in CLAUDE.md.

## Testing & rollout

- Each skill is runnable locally in interactive Claude Code; a dry-run convention posts to
  `#test` (`DISCORD_TEST_CHANNEL_ID`) instead of DM.
- **Setup step zero**: test whether the work Google account can connect to claude.ai
  connectors. If blocked, apply the calendar-sharing fallback and move work-email triage
  to the roadmap.
- Rollout order: morning briefing → run reliably for a few days → evening shutdown →
  weekly review. One routine at a time.

## Usage/cost

~15 routine runs/week drawing on the claude.ai subscription (routines require Pro/Max with
Claude Code on the web enabled). Routines are a research preview; if the surface changes,
the repo's skills are portable to local cron/launchd (only `docs/setup.md` and scheduling change).

## Roadmap (later phases)

1. People pages (colleagues/friends: last conversation, open loops, birthdays) powering
   meeting prep and relationship memory.
2. Decision log (append-only decisions + reasoning).
3. Monthly pattern reports from accumulated Journal data.
4. Full two-way Discord assistant (always-on bot on a small host, Dominik-Britz-style).
5. Meeting-prep briefs before each event (needs sub-hourly triggers or the always-on bot).
6. Weather + "leave by" enrichment in the morning briefing.
7. Work-email triage if the connector is blocked at launch.
8. Knowledge ingestion (the original article's core idea): drop books/articles/links into
   the brain and have Claude build cross-linked concept notes in Notion — the Reading
   list's `Unread` items become the ingestion queue.
9. Voice-memo capture: audio posted to `#capture` gets transcribed and triaged like text.
10. Birthday/anniversary lead-time warnings in the morning briefing (feeds off People pages).
11. Health/fitness data in the briefing (Strava/Whoop/Apple Health exports).
12. News & interests digest: a curated section in the morning briefing on topics you follow.
13. Spaced resurfacing: the briefing occasionally resurfaces an old note or decision
    ("you wrote this 3 months ago — still true?").

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
    discord.sh                   # send DM, fetch capture messages (paginated), add ✅ reactions
    check-env.sh                 # validate env vars + Discord/GitHub/Notion connectivity
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
| Notion | claude.ai Notion connector **+ REST token for structured reads** | Connector for creation/content/search; see 2026-07-07 note |
| Gmail/Calendar (personal) | claude.ai Google connectors | |
| Gmail/Calendar (work) | claude.ai Google connectors **if** Simply Business IT allows | Fallback: share work calendar into personal calendar; work email drops to roadmap |
| Discord | Bot token + REST via `curl` (`scripts/discord.sh`) | No hosted MCP dependency |
| GitHub | `gh` CLI with `GH_TOKEN` | Fine-grained PAT + explicit repo allowlist in CLAUDE.md |

> **2026-07-06 (Stage 0):** The brain is hosted on Stanton's **personal** claude.ai
> account (Pro), not the Simply Business workspace: the work Claude org blocks
> Gmail/Google Calendar connectors at org level, and connectors cannot be bridged
> between accounts. The Notion workspace (including `CSD EL`) is Stanton's own, so the
> Notion connector also runs on the personal account.
>
> **2026-07-06 (setup step zero result):** the **work** Google account cannot connect
> on the personal claude.ai account either — blocked on the Google Workspace side.
> Work-email triage stays on the roadmap (item 7). The calendar-sharing fallback is
> agreed but **not yet applied** (tracked as a TODO): share the work calendar into the
> personal Gmail account ("See all event details", or free/busy if org policy caps it).
> Until then, briefings cover the personal calendar only. Longer-term alternative: ask
> the Simply Business Google Workspace admin to allowlist the Claude connector app
> (Admin console → Security → API controls → App access control), which would unlock
> both work calendar and work-email triage directly.
>
> **2026-07-07 (Stage 2, agreed option A):** the Notion connector's structured-query
> tools (SQL and view mode) are plan-gated behind Business + Notion AI, which Stanton's
> plan lacks — creates/updates/fetch/search work, exhaustive row queries do not.
> Deviation: structured **reads** (rolling list, capture cursor, journal week, aging)
> and page **archival** go via a free Notion internal-integration token
> (`NOTION_TOKEN` env var) against the public REST API (`api.notion.com`, version
> 2025-09-03 data-source endpoints) through `scripts/notion.sh` — same
> token-plus-curl pattern as Discord. The connector remains the path for page
> creation, content writing, and search. Cloud network allowlist gains
> `api.notion.com`. CSD EL read-only remains a behavioural rule (token capabilities
> are workspace-wide, not per-page).
>
> **2026-07-09 (Stage 4, agreed):** the connector's write tools proved unreliable in
> cloud sessions — the scheduled morning run of 2026-07-09 could query but had no
> `create-pages`/`update-page` tools (enabledInChat-style regression, second
> occurrence), so the DM was delivered with a ⚠️ and the Journal page had to be
> backfilled locally from the DM text. Deviation, at Stanton's direction ("the notion
> MCP is unreliable, let's work around it"): **all Notion writes** move to
> `scripts/notion.sh` (new TDD'd commands `create`, `set-props`, `append` against the
> REST API; the `NOTION_TOKEN` integration already has read+update+insert
> capabilities). The connector is reduced to search and interactive reads. CSD EL
> read-only and the Habit Tracker / DnD exclusions remain behavioural rules, unchanged.

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
    Domain (`Work / Personal`), Project/Area (select), Due (date),
    Priority (`High / Medium / Low`), Created (created time), Completed (date),
    Waiting-on (text: person), Blocked Reason (text, used with `Waiting`),
    Snoozed Until (date — hidden from briefings until then),
    Pinned (checkbox — exempt from aging flags and cull proposals),
    Rollover Count (number), Last Rolled Over (date), Last Touched (date),
    Source (text: human-readable origin), Source ID (text: unique dedupe key —
    Discord message ID, Gmail message ID, GitHub PR URL, or `manual`).
  - The rolling list = view of `Next + In progress + Waiting`, excluding snoozed.
  - Rollover state lives in these properties, updated by the evening run — never
    parsed back out of Journal prose.
- **Journal** (database) — one page per run, titled by run ID (see Run conventions):
  Date, Type (`Morning / Evening / Weekly`), body = full text of what was sent. Memory
  for the weekly self-check and future pattern analysis.
- **Capture Log** (database) — the authoritative record of capture processing, one row
  per Discord message: Message ID (dedupe key), Raw Text, Processed At, Outcome
  (`Task created / Reading list / Note / Status update / Needs Review / Skipped`),
  Confidence, and a link to the created/updated Task or Journal page. Gives dedupe,
  audit, and retry safety independent of Discord reaction state.
- **Reading list** (database) — Name, URL, Status (`Unread / Read`), Added.
- **Brag doc** (page) — appended by the weekly review, grouped by month.

### Aging rules (in CLAUDE.md)

- Task in `Next`/`In progress` for **>14 days** → flagged in briefings with its age.
- **>30 days** → weekly review proposes moving it to `Dropped` (user confirms via capture reply).
- **Pinned** tasks are exempt from both; **snoozed** tasks don't age until they wake.

## Discord design

- Private server ("Second Brain") containing the bot; channels `#capture` and `#test`.
- Briefings arrive as **DMs** from the bot (POST `/users/@me/channels` with
  `DISCORD_USER_ID`, then post; respect 2000-char limit by splitting).
- Bot needs the **Message Content privileged intent** (toggle in the dev portal) and
  read/send/reaction permissions.

### Capture protocol

- Each run pages through `#capture` history with the `after` cursor (100 messages/page)
  until fully caught up — never a "recent messages" window that could miss older items
  if volume spikes.
- The **Capture Log is the source of truth** for what's been processed (dedupe by message
  ID). The ✅ reaction is a UX marker only, added after the Capture Log row is written —
  so a retry after partial failure can't double-process.
- Discord API calls honor rate limits (429 + `Retry-After`, exponential backoff) and
  DM sends split at the 2000-character limit.
- Triage intent rules (in CLAUDE.md):
  - URL → Reading list.
  - `done: <text>` / `drop: <text>` → fuzzy-match an existing Task and update Status —
    **only above a confidence threshold**. Ambiguous matches become a `Needs Review`
    Capture Log row surfaced in the next DM's decisions-needed section; never guess.
  - `snooze: <task> until <date>` → set Snoozed Until.
  - `waiting: <person> <thing>` → Task with Status `Waiting` + Waiting-on.
  - `note: <text>` → forced journal note (skips task inference).
  - Anything actionable → Task (infer Domain, Due, Priority; default Status `Inbox`,
    promoted to `Next` if clearly actionable).
  - Otherwise → appended as a note to today's Journal page.
- Every processed capture is confirmed in the next briefing/shutdown ("Captured: 3 tasks, 1 link").

## Run behavior

### Run conventions

- **Timezone**: all date queries, Journal titles, and "today/tomorrow" logic resolve in
  **Europe/London** explicitly (cloud runs default to UTC — never rely on system time).
- **Run ID**: `{type}-{YYYY-MM-DD}` (e.g. `morning-2026-07-06`); manual reruns append a
  suffix note but target the same Journal page.
- **Idempotency**: before writing, each run checks for an existing Journal page with its
  run ID and updates it rather than duplicating; captures are already idempotent via the
  Capture Log. A manual rerun therefore never double-creates tasks or Journal entries.

### Morning briefing (06:45)

1. Triage unprocessed captures.
2. Calendar: today's events across both accounts, gaps noted.
3. Tasks: pick **top 3** (due date, priority, aging), then the rest of the rolling list one line each.
4. Email: messages needing replies; deadlines spotted; **waiting-on** = sent mail from the
   last 7 days with no reply.
5. GitHub: PRs awaiting my review; my open PRs' status; CI failures overnight — across
   an explicit **repo allowlist in CLAUDE.md** (and a fine-grained PAT scoped to match),
   not everything the token can see.
6. Aging flags (>14 days, unpinned only).
7. **Decisions needed**: `Needs Review` Capture Log rows and anything else awaiting a call.
8. Compose in the CLAUDE.md format → DM → save full text to Journal.

### Evening shutdown (21:00)

1. Triage captures, including `done:`/`drop:`/`snooze:`/`waiting:` updates.
2. Reconcile: Tasks completed today (Notion status changes + capture messages);
   set Last Touched.
3. **Honest rollover**: incomplete due-today items get Rollover Count incremented and
   Last Rolled Over set, then listed with their count ("X rolled over, 4th time") —
   read from Task properties, never parsed from Journal prose.
4. **Decisions needed**: unresolved `Needs Review` items carried forward.
5. Tomorrow preview: first meeting, day shape.
6. DM → Journal.

### Weekly review (Sunday 17:00)

1. Read the week's Journal pages + Tasks activity + recently updated `CSD EL` sub-pages.
2. Compose: wins, dropped balls, stale-task cull proposals (>30 days, unpinned),
   next week's shape.
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

- `scripts/check-env.sh` validates required env vars and live connectivity (Discord auth,
  `gh auth status`, Notion connector reachable) — run before enabling each routine.
- Each skill is runnable locally in interactive Claude Code; a dry-run convention posts to
  `#test` (`DISCORD_TEST_CHANNEL_ID`) instead of DM, and a **fixture mode** feeds canned
  Discord/Notion/GitHub data so triage and composition logic can be exercised without
  touching live services.
- **Setup step zero**: test whether the work Google account can connect to claude.ai
  connectors. If blocked, apply the calendar-sharing fallback and move work-email triage
  to the roadmap.
- Rollout order: morning briefing → run reliably for a few days → evening shutdown →
  weekly review. One routine at a time. Phase 2 starts only after the core has run
  reliably for at least a week.

## Usage/cost

~15 routine runs/week drawing on the claude.ai subscription (routines require Pro/Max with
Claude Code on the web enabled). Routines are a research preview; if the surface changes,
the repo's skills are portable to local cron/launchd (only `docs/setup.md` and scheduling change).

## Phase 2 (committed, after the core runs reliably)

> **2026-07-12 (planning gate opened early, at Stanton's direction):** the core
> (Stages 0–5) is complete and live (commit `b7d2633`; morning 06:45, evening 21:00,
> weekly Sunday 17:00 all verified in production). Stanton has opened the Phase 2
> **planning** gate ahead of the full reliability week: plans for Stages 6–11 are
> written now. **Execution of any Phase 2 stage still waits for Stanton's explicit
> go**, stage by stage, per each plan's ✋ checkpoints — nothing ships from writing the
> plans. The reliability bar is unchanged: **Sunday 19 Jul 2026's weekly self-check
> must come back clean (or every gap explained)** before Phase 2 code is enabled in
> production. Build order below is unchanged.

> **2026-07-12 (Phase 2 surface verification, before writing Stages 6 & 8):** checked
> the real claude.ai routines surface against the spec's guesses. Findings are from the
> Claude Code routines documentation (which post-dates this repo's Jan-2026 baseline);
> **Stanton's own Routines UI on the personal account is authoritative for exact values.**
> - **Item 1 (on-demand trigger):** confirmed in principle — routines expose an
>   on-demand **fire** endpoint (documented shape: `POST …/routines/{id}/fire` with a
>   per-routine bearer token, an experimental `anthropic-beta` routine header, and an
>   optional `{"text": …}` run-context body) **and** a **"Run now"** button in the UI.
>   The spec's `/fire` assumption stands, so Stage 6 proceeds. The exact URL, header, and
>   token are read off Stanton's Routines UI in Stage 6 Task 1 (only he can see them; the
>   token value is never pasted into chat). If that UI shows only "Run now" and no
>   external endpoint, that is a reality difference → Stage 6 stops and falls back to the
>   documented alternative rather than inventing an endpoint.
> - **Item 3 (backup push):** cloud routine runs push to GitHub under a **`claude/`-prefixed
>   branch by default**; a per-repo **"Allow unrestricted branch pushes"** toggle in the
>   routine's permissions enables direct pushes to `main`. Both paths are viable for the
>   weekly backup; **Stanton chose direct-to-`main` (2026-07-12)** for zero weekly
>   friction — Stage 8 enables the unrestricted-pushes toggle on `second-brain` and the
>   weekly routine commits backups straight to `main`.

In build order:

1. **On-demand briefing ("brief me now")** — add an API trigger to the morning-briefing
   routine; an iOS Shortcut POSTs to the routine's `/fire` endpoint, with optional text
   passed as run context (e.g. "focus on this evening"). Same skill, ad-hoc run ID,
   DM delivery. Closes most of the gap to a two-way assistant with no extra infrastructure.
2. **Dead-man's switch** — each run ends by pinging a per-routine healthchecks.io URL
   (`HEALTHCHECK_URL_MORNING/EVENING/WEEKLY` env vars); a missed ping alerts by email/push
   the same day. Catches runs that never started — the failure mode the weekly self-check
   only notices on Sunday. **🚫 SKIPPED 2026-07-14 (Stanton's decision): "we don't need
   this" — descoped, not built. Plan `2026-07-12-stage-7-dead-mans-switch.md` retained for
   the record; revivable if same-day miss-alerting is ever wanted.**
3. **Weekly Notion backup** — the weekly run exports the Second Brain databases (Tasks,
   Journal, Capture Log, Reading list, Brag doc) to markdown/JSON under `backups/` and
   commits to this repo. Requires enabling unrestricted branch pushes for this repo, or
   merging from a `claude/`-prefixed backup branch.
4. **`meeting:` capture pipeline** — raw meeting notes pasted into `#capture` with a
   `meeting:` prefix become a structured note (attendees, decisions, actions) in the
   Second Brain section, with action items extracted into Tasks. `CSD EL` stays read-only.
5. **Recurring tasks** — adds a Recurrence property (natural-language rule, e.g.
   "every Sunday") to Tasks; when the evening run reconciles a completed recurring task,
   it spawns the next instance with the next due date.
6. **Time-block proposals** — the morning briefing suggests which of today's calendar gaps
   fit the top 3 tasks. Actually writing events into the calendar is a separate, later decision.
7. **121 action-point ingestion** *(added 2026-07-08, Stanton's request)* — 1:1 notes are
   pages titled `DDMMYYYY - 121` under `CSD EL → Direct Reports → {person} → {year}`.
   A daily run scans — **read-only, as CSD EL always is** — for 121 pages edited since
   its last scan and turns bullets under an "Action points"/"Actions" heading — only
   those (agreed 2026-07-08; Stanton keeps the heading convention, notes without the
   section are skipped by design) — into Tasks: Domain `Work`, Status `Inbox`,
   Source = the 121 page, Source ID = `{page-id}#{bullet-key}` so reruns can't
   duplicate (dedupe lives in Tasks; CSD EL is never written, so no ingested-marker
   there). Shares extraction logic with item 4's `meeting:` pipeline — build adjacent.
8. **Siri voice capture** *(added 2026-07-10, Stanton's request)* — an iOS Shortcut
   posts dictated text into `#capture` via a Discord webhook; the brain is unchanged
   (the capture protocol triages any non-self message; CLAUDE.md clarified 2026-07-10
   that only the bot's own user ID is ignored, so webhook-authored messages are valid).
   Phone-side setup steps in `docs/setup.md` §7. **No brain code and no build stage —
   it does not wait for the Phase 2 gate and can be enabled immediately.**

## Roadmap (possible later phases)

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

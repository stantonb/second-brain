---
name: morning-briefing
description: Compose and deliver the ~7am morning briefing DM — capture triage, today's calendar, top-3 tasks, email triage, GitHub PRs/CI, aging flags, decisions needed. Use for the daily 06:45 routine or an on-demand "brief me".
---

# Morning briefing

Read `CLAUDE.md` in full first — identity, workspace map (with hard exclusions), triage
rules, the Morning format, the GitHub repo allowlist, the Notion access split, and the
Europe/London rule all bind this run. Rule #1: never fail silent.

## Modes

| Env | Effect |
|---|---|
| `FIXTURE_MODE=1` | Read `tests/fixtures/**` per the mapping in `tests/fixtures/README.md` instead of live services. No network, **no Notion writes, no Discord sends** — print the composed briefing to stdout plus a "Would write:" list of every mutation that production would have made. |
| `DRY_RUN=1` | Live reads and real capture triage (it is idempotent), but delivery goes to `#test` via `./scripts/discord.sh send-channel "$DISCORD_TEST_CHANNEL_ID"` and the run ID gets a `-test` suffix. |
| (neither) | Production: DM via `send-dm`, Journal under the plain run ID. |

## Access split (from CLAUDE.md)

- **Exhaustive reads** (rolling list, capture cursor, aging scans):
  `./scripts/notion.sh query <data-source-id> '<filter-json>'` — full pagination,
  never a search-based or partial read. Data-source IDs are in CLAUDE.md.
- **Creates, content writes, search**: the Notion connector tools.
- **All Discord I/O**: `./scripts/discord.sh`.

## Procedure

0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)`. Run ID
   `morning-$TODAY` (plus `-test` in DRY_RUN). Query the Journal data source for
   `{"property":"Name","title":{"equals":"<run-id>"}}`: if a page exists this is a
   rerun — update that page and note "(rerun)"; never create a duplicate.
1. **Triage captures.**
   - Cursor = highest Message ID across Capture Log rows (query the Capture Log data
     source, take max title; `0` if none).
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
3. **Tasks.** Rolling list = `notion.sh query` on the Tasks data source with filter
   Status ∈ {Next, In progress, Waiting} (or-group of selects), then drop rows whose
   Snoozed Until is after TODAY. Pick the **top 3** by: overdue/due-today first, then
   Priority (High→Low), then age (days since Last Touched, fallback Created; oldest
   first). Everything else gets one line each.
4. **Email.** From Gmail: inbox messages that need a reply; explicit deadlines spotted;
   waiting-on = my sent mail from the last 7 days with no reply on the thread.
5. **GitHub.** If CLAUDE.md's allowlist is pending or `GH_TOKEN` is absent: one line —
   "⚠️ GitHub: pending (allowlist/PAT not configured)" — this is configuration, not an
   outage. Otherwise, for each allowlisted repo ONLY:
   - `gh pr list --repo "$REPO" --search "review-requested:@me" --state open --json number,title,url`
   - `gh pr list --repo "$REPO" --author "@me" --state open --json number,title,url,reviewDecision,statusCheckRollup`
   - CI failed overnight = my open PRs with any `statusCheckRollup` conclusion `FAILURE`.
6. **Aging flags.** Rolling-list tasks (unpinned, unsnoozed, Status `Next`/`In
   progress`) whose age > 14 days → ⏳ with age in days.
7. **Decisions needed.** Capture Log rows with Outcome `Needs Review` that are still
   unresolved, plus anything else awaiting Stanton's call.
8. **Compose, deliver, journal.**
   - Compose exactly per `CLAUDE.md → ## Briefing formats → Morning`. Omit empty
     sections. One ⚠️ line at the bottom per unreachable service.
   - Deliver per mode (stdin pipe into `discord.sh`).
   - Write the full delivered text to the Journal page (title = run ID, Date = TODAY,
     Type = `Morning`) via the connector — **even if Discord delivery failed**.

## Never

- Write to Notion outside the Second Brain section; read Habit Tracker or DnD.
- Skip delivery because one service failed (rule #1 — send what succeeded, flag the rest).
- Add a ✅ reaction before its Capture Log row exists.
- Read GitHub repos outside the allowlist.
- List tasks from search results — exhaustive reads come from `notion.sh query` only.

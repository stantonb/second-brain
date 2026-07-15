---
name: morning-briefing
description: Compose and deliver the ~7am morning briefing DM — capture triage, today's calendar, top-3 tasks, email triage, GitHub PRs/CI, aging flags, decisions needed, individual reminder DMs for overdue/due-today/snooze-waking tasks. Use for the daily 06:45 routine or an on-demand "brief me".
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
| `ON_DEMAND=1` (+ optional `BRIEF_FOCUS="..."`) | On-demand "brief me now": run ID `morning-$TODAY-ondemand-$(TZ=Europe/London date +%H%M%S)`, DM delivery, **never touch the scheduled `morning-$TODAY` page**. If `BRIEF_FOCUS` is set, weave it into ordering/emphasis and note it in the header. In production this same mode is triggered by run-context text injected via the routine's fire endpoint — the Shortcut always sends non-empty text, so **any** fire run is on-demand; treat that text as `BRIEF_FOCUS`, except a bare `brief me`/`brief me now` sentinel means on-demand with **no** focus. Only the cron schedule (no injected text) is the normal scheduled briefing. Combine with `DRY_RUN=1` to deliver an on-demand test to `#test`. 121 action-point ingestion does **not** run on an on-demand brief-me — it is scheduled-run-only. |

## Access split (from CLAUDE.md)

- **Exhaustive reads** (rolling list, capture cursor, aging scans):
  `./scripts/notion.sh query <data-source-id> '<filter-json>'` — full pagination,
  never a search-based or partial read. Data-source IDs are in CLAUDE.md.
- **Creates, content writes, search**: the Notion connector tools.
- **All Discord I/O**: `./scripts/discord.sh`.

## Procedure

0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)`.
   - **Scheduled/normal run** (no `ON_DEMAND`, and no injected run-context text — i.e. the
     cron schedule): run ID `morning-$TODAY` (plus `-test` in DRY_RUN). Query the Journal
     database (ID in CLAUDE.md) for a page titled with the run ID: if it exists this is a
     rerun — update that page and note "(rerun)"; never create a duplicate.
   - **On-demand run** (`ON_DEMAND=1`, or **any** run-context text was injected by the fire
     endpoint — the Shortcut always sends non-empty text, so every fire lands here): run ID
     `morning-$TODAY-ondemand-$(TZ=Europe/London date +%H%M%S)` (plus `-test` in DRY_RUN).
     This is always a fresh page — do **not** look up or update the scheduled
     `morning-$TODAY` page. Focus: if the injected text (or `$BRIEF_FOCUS`) is a bare
     `brief me`/`brief me now` sentinel, there is **no** focus — compose the normal Top-3
     with no focus line. Otherwise treat the text as focus: bias the Top-3 ordering/emphasis
     toward it and add a one-line "🎯 On-demand brief — focus: {text}" under the header.
     Deliver as a DM (or to `#test` under DRY_RUN) exactly like the scheduled run.
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
2. **121 action-point ingestion** (scheduled run only — skip entirely on an on-demand run,
   and on a rerun where step 0 found the scheduled run ID's Journal page already existed).
   Per `CLAUDE.md → ## 121 action-point ingestion`: walk CSD EL Direct Reports with
   `./scripts/notion.sh get-blocks`, extract **Stanton's own** items under the
   `Action Items`/`Follow-ups` sections (skip a report's own actions; strip the
   `Stanton —` prefix and any `(carried over)` marker), and `./scripts/notion.sh create`
   a deduped `Inbox`/`Work` Task per **new** action (`Source ID` `121:{person}#{bullet-key}`,
   content-based, dedupe by querying Tasks for `Source ID starts_with "121:"`). Collect the
   newly-created actions for the
   `🗂 New from 1:1s` section (step 9's compose). On **any** read failure: create nothing,
   add `⚠️ couldn't reach CSD EL 1:1 notes` (rule #1). In `FIXTURE_MODE` read the walk,
   page blocks, and existing Source IDs from the fixtures (`tests/fixtures/README.md`
   mapping) and list each `create` under "Would write:".
3. **Calendar.** Today's events from every connected Google Calendar (personal account;
   plus the shared work calendar if that fallback is live). List chronologically with
   times; note gaps ≥ 45 min between 09:00–18:00. For work meetings, context may be
   pulled from `CSD EL` sub-pages — **read-only** — when a one-liner would help.
4. **Tasks.** Rolling list = `notion.sh query` on the Tasks data source with filter
   Status ∈ {Next, In progress, Waiting} (or-group of selects), then drop rows whose
   Snoozed Until is after TODAY. Pick the **top 3** by: overdue/due-today first, then
   Priority (High→Low), then age (days since Last Touched, fallback Created; oldest
   first). Everything else gets one line each.
5. **Email.** From Gmail: inbox messages that need a reply; explicit deadlines spotted;
   waiting-on = my sent mail from the last 7 days with no reply on the thread.
6. **GitHub.** First `source ./scripts/gh-token.sh` so `gh` authenticates with our PAT
   (`GH_PAT`); the cloud host otherwise exposes a repo-scoped `GH_TOKEN` that sees only
   `second-brain` and would ⚠️ every other allowlisted repo. If CLAUDE.md's allowlist is
   pending or no GitHub token (`GH_PAT`/`GH_TOKEN`) is set: one line —
   "⚠️ GitHub: pending (allowlist/PAT not configured)" — this is configuration, not an
   outage. Otherwise, for each allowlisted repo ONLY:
   - `gh pr list --repo "$REPO" --search "review-requested:@me" --state open --json number,title,url`
   - `gh pr list --repo "$REPO" --author "@me" --state open --json number,title,url,reviewDecision,statusCheckRollup`
   - CI failed overnight = my open PRs with any `statusCheckRollup` conclusion `FAILURE`.
7. **Aging flags.** Rolling-list tasks (unpinned, unsnoozed, Status `Next`/`In
   progress`) whose age > 14 days → ⏳ with age in days.
8. **Decisions needed.** Capture Log rows with Outcome `Needs Review` that are still
   unresolved, plus anything else awaiting Stanton's call.
9. **Compose, deliver, journal.**
   - Compose exactly per `CLAUDE.md → ## Briefing formats → Morning`. Omit empty
     sections. One ⚠️ line at the bottom per unreachable service.
   - Deliver per mode (stdin pipe into `discord.sh`).
   - Write the full delivered text to the Journal page (title = run ID, Date = TODAY,
     Type = `Morning`) via the connector — **even if Discord delivery failed**.
10. **Individual reminder notifications** (CLAUDE.md → Discord → individual reminder
   notifications). Skip this step entirely for an **on-demand** run, or if step 0 found
   the scheduled run ID's Journal page already existed (this is a rerun — the reminder
   DMs already went out earlier today).
   - **Query the reminder set directly** — do **not** reuse step 4's rolling list, which
     omits `Inbox` tasks (a freshly captured task due today can sit in `Inbox`). Run one
     `notion.sh query` on the Tasks data source for every non-`Done`/`Dropped` task that
     is due on/before today or waking today (substitute the real `$TODAY`):

     ```json
     {"and":[
       {"property":"Status","select":{"does_not_equal":"Done"}},
       {"property":"Status","select":{"does_not_equal":"Dropped"}},
       {"or":[
         {"property":"Due","date":{"on_or_before":"$TODAY"}},
         {"property":"Snoozed Until","date":{"equals":"$TODAY"}}
       ]}
     ]}
     ```

     Then **drop any task still snoozed** (`Snoozed Until` after `$TODAY`) — snoozing
     hides a task even when it is overdue.
   - Classify each remaining task and send exactly one DM per task, first match wins:
     - `Due` before `$TODAY` → `⏰ Overdue: {name} (due {Ddd D Mon})`
     - `Due` = `$TODAY` → `⏰ Due today: {name}`
     - else (`Snoozed Until` = `$TODAY`) → `⏰ Back from snooze: {name}`
     - Production: `printf '%s' "$MSG" | ./scripts/discord.sh send-dm`.
     - `DRY_RUN=1`: `printf '%s' "$MSG" | ./scripts/discord.sh send-channel "$DISCORD_TEST_CHANNEL_ID"`.
     - `FIXTURE_MODE=1`: no send — list each message under "Would send:".

## Never

- Write to Notion outside the Second Brain section; read Habit Tracker or DnD.
- Skip delivery because one service failed (rule #1 — send what succeeded, flag the rest).
- Add a ✅ reaction before its Capture Log row exists.
- Read GitHub repos outside the allowlist.
- List tasks from search results — exhaustive reads come from `notion.sh query` only.
- Re-fire individual reminder DMs on an on-demand run or on a rerun of the scheduled run.
- Write, append to, rename, or mark CSD EL — the 121 ingestion is strictly read-only there.
- Run 121 ingestion on an on-demand run, or re-create ingested actions on a rerun (Source-ID dedupe must hold).

---
name: evening-shutdown
description: Compose and deliver the 9pm evening shutdown DM — capture triage incl. done/drop/snooze/waiting updates, completion reconciliation, honest task rollover with counts, tomorrow preview. Use for the daily 21:00 routine.
---

# Evening shutdown

Read `CLAUDE.md` in full first. Rule #1: never fail silent.

## Modes

Identical contract to `morning-briefing`:
`FIXTURE_MODE=1` (fixtures per `tests/fixtures/README.md`, no network/writes, print
briefing + "Would write:" list) · `DRY_RUN=1` (live reads + real triage, deliver to
`#test`, run ID suffixed `-test`) · production (DM + Journal).

## Procedure

0. **Dates & idempotency.** `TODAY=$(TZ=Europe/London date +%F)`;
   `TOMORROW=$(TZ=Europe/London date -v+1d +%F)` locally (`date -d '+1 day' +%F` on
   Linux cloud runs). Run ID `evening-$TODAY`. Same Journal rerun check as morning.
1. **Triage captures** — same protocol as morning (cursor from Capture Log, dedupe,
   Capture Log row before ✅). Evening is where `done:` / `drop:` / `snooze:` /
   `waiting:` status updates mostly land — apply CLAUDE.md rule 2's confidence gate
   strictly: ambiguous match → `Needs Review`, never guess.
1b. **Poll reminder reactions → complete tasks** (`CLAUDE.md → Discord →
   Reaction-to-complete`). Runs on every evening run, **before** completion reconciliation
   (step 2) and rollover (step 3) so reacted tasks are counted done, not rolled over.
   - **Watch set:** `./scripts/notion.sh query <tasks-ds>` with

     ```json
     {"and":[
       {"property":"Reminder Message ID","rich_text":{"is_not_empty":true}},
       {"property":"Status","select":{"does_not_equal":"Done"}},
       {"property":"Status","select":{"does_not_equal":"Dropped"}}
     ]}
     ```

   - **Channel:** production → `CH=$(./scripts/discord.sh dm-channel)`; `DRY_RUN=1` →
     `CH=$DISCORD_TEST_CHANNEL_ID`; `FIXTURE_MODE=1` → read
     `tests/fixtures/discord/reminder-reactions.json` + `tests/fixtures/notion/tasks-reminder-watch.json`,
     treating the `STANTON` sentinel as `$DISCORD_USER_ID`.
   - For each watched task, `AFFIRMED=$(./scripts/discord.sh reactors "$CH" "$MSGID" ✅ 👍)`.
     If `$DISCORD_USER_ID` is in that array, mark the task **Done** via
     `./scripts/notion.sh set-props <page-id>`:

     ```json
     {"Status":{"select":{"name":"Done"}},
      "Completed":{"date":{"start":"$TODAY"}},
      "Last Touched":{"date":{"start":"$TODAY"}}}
     ```

     Keep the list of task names completed here — step 2 tags them.
   - **Rule #1:** on any `dm-channel`/`reactors` failure, don't abort — finish the run and add
     `⚠️ couldn't check reminder reactions` at the bottom. In `FIXTURE_MODE`, list each
     completion `set-props` under "Would write:".
2. **Reconcile completions.** Query Tasks for Status `Done` with empty Completed →
   set Completed = TODAY, Last Touched = TODAY (these are tasks Stanton ticked off in
   Notion himself). "Done today" for the DM = all tasks with Completed = TODAY,
   whether from Notion edits or `done:` captures.
   Tasks completed by the reaction poll (step 1b) have Completed = TODAY, so they appear in
   "Done today" automatically; suffix those lines " — by reaction" so the source is clear.
3. **Honest rollover.** Query Tasks for Due ≤ TODAY with Status ∈ {`Next`,
   `In progress`, `Waiting`} (unsnoozed). Skip any task whose Last Rolled Over is
   already TODAY (rerun guard — a manual rerun must not double-increment). For each
   remaining task: Rollover Count += 1, Last Rolled Over = TODAY. Due is left unchanged — overdue is information, not
   something to hide. List each in the DM with its ordinal count ("3rd time"). Counts
   come from the Task properties just written — never parsed from Journal prose.
4. **Decisions needed.** Unresolved `Needs Review` Capture Log rows, carried forward.
5. **Tomorrow preview.** First meeting and one-line day shape from tomorrow's calendar
   across connected accounts.
6. **Compose, deliver, journal.** Compose exactly per `CLAUDE.md → ## Briefing formats
   → Evening`; omit empty sections; ⚠️ lines for unreachable services. Deliver per
   mode. Journal page (title = run ID, Date = TODAY, Type = `Evening`) with the full
   text — even if Discord failed.

## Never

- Write outside Second Brain; read Habit Tracker or DND.
- Change a Due date during rollover, or infer rollover state from prose.
- Guess on ambiguous `done:`/`drop:` matches.
- Skip delivery because a service failed.

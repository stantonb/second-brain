# Reaction-to-complete — design

*Date: 2026-07-15. Feature: mark a Task done by reacting to the individual reminder DM
the second brain sends, instead of typing `done:` in the capture channel.*

## Problem

Completing a task currently requires a `#capture` message (`done: <text>` or an
unprefixed natural-language completion), which is then fuzzy-matched to an open task
under the "one unambiguous match" gate. Stanton wants a lighter path: react to the
individual reminder DM the brain already pushes for a task, and have that mark the task
done.

## Decisions (from brainstorming)

1. **Reactable surface: the individual reminder DMs only.** The morning run already
   sends one standalone DM per overdue / due-today / snooze-waking task (CLAUDE.md →
   Discord → individual reminder notifications). Each is exactly one task, so a reaction
   maps unambiguously. The batched briefing (many tasks in one message) is **not**
   reactable and stays read-only. Only tasks that received a reminder DM are completable
   by reaction.
2. **Pickup timing: at the next run.** There is no always-on Discord listener — the
   brain is scheduled/on-demand batch runs. Reactions are polled during the existing
   **morning and evening** runs. React during the day → evening shutdown marks it done
   and reports it; next morning it is off the list. No new cron routine, no gateway
   process.
3. **Done signal: an affirmative-reaction allowlist, default `✅` and `👍`.** Either
   completes the task. A stray off-allowlist emoji does not. The allowlist is a constant
   the poll reads, extensible later (e.g. `😴` → snooze) without touching the mechanism.
4. **Mechanism: explicit stored mapping (Approach A).** The reminder DM's message ID is
   stored on the Task; the poll checks that exact message. No fuzzy matching, no
   Needs-Review gate — the message *is* the task.

## Data model

**New Task property: `Reminder Message ID` (text).** Internal plumbing, like `Source
ID`. Holds the Discord message ID of the **most recent** individual reminder DM sent for
that task. Empty for tasks never reminded. The DM channel is stable (reopened any time
via `POST /users/@me/channels`), so only the message ID is stored — not the channel ID.

CLAUDE.md Task-schema table gains:

| Property | Type | Meaning |
|---|---|---|
| Reminder Message ID | text | Discord message ID of the most recent individual reminder DM for this task; polled for an affirmative reaction (✅/👍) from Stanton to auto-complete |

## `discord.sh` additions

The affirmative allowlist is a constant in the poll logic (skills), not in
`discord.sh`; `reactors` takes the emoji(s) to check as arguments so the script stays
generic.

- **`send-reminder [channel_id]`** — send a single short message (one chunk) from stdin
  and **print the created message's ID** to stdout. With no argument it DMs
  `$DISCORD_USER_ID` (production); with a `channel_id` it posts there (`#test` under
  `DRY_RUN`). This one command therefore covers both routing modes and always returns
  the ID. Existing `send-dm` / `send-channel` are unchanged, so briefings are
  unaffected.
  - Note: `send-channel` chunks and discards message IDs; `send-reminder` is a distinct
    single-message path that returns the ID. Reminder DMs are always one line, so a
    single POST is correct.
- **`reactors <channel_id> <message_id> [emoji...]`** — for each emoji given (default:
  the affirmative allowlist), call `GET
  /channels/{channel}/messages/{message}/reactions/{emoji}` and print the **union** of
  reacting user IDs (JSON array, deduped). The poll checks whether `$DISCORD_USER_ID` is
  in that set. Honours the existing `DISCORD_API_BASE` test seam and 429 handling.

The `usage()` block and command dispatch in `discord.sh` are updated for both.

## Flow

### Phase 1 — record on send (morning run only)

In the morning run's individual-reminder-notifications step, each reminder DM is sent
via `send-reminder` instead of `send-dm`, and the returned message ID is written to that
task's `Reminder Message ID` via one `notion.sh set-props`.

- **Production:** `send-reminder` (no channel arg) DMs Stanton; real `set-props`.
- **`DRY_RUN=1`:** `send-reminder "$DISCORD_TEST_CHANNEL_ID"` posts to `#test` and
  returns the ID; the ID is still stored, so the full loop is testable against `#test`.
  *(`reactors` works on any channel, so the DRY_RUN poll reads `#test` message IDs the
  same way.)*
- **`FIXTURE_MODE=1`:** no send, no write — the `set-props` is listed under "Would
  write:" like every other mutation.

Reminder-send guarding is unchanged from today: reminders do **not** re-fire on a rerun
of the scheduled morning run; only the ID capture is added to the existing send.

### Phase 2 — poll & complete (morning and evening runs)

A shared step at the completion-reconciliation point (evening SKILL step 2; a matching
step in the morning SKILL, adjacent to capture triage):

1. Query Tasks for **non-empty `Reminder Message ID`** and **Status ∉ {Done, Dropped}**
   — the bounded watch set. Done/Dropped tasks drop out automatically.
2. Open the DM channel once. For each watched task, call `reactors` on its stored
   message ID with the affirmative allowlist.
3. If `$DISCORD_USER_ID` is in the returned set → mark the task **Done**: Status = Done,
   Completed = TODAY (Europe/London poll date), Last Touched = TODAY.
4. Reaction-completed tasks feed the DM's **✅ Done today** section, tagged to show the
   source, e.g. `{task} — completed by reaction`, alongside `done:`-capture and
   Notion-edit completions.

No fuzzy match, no Needs-Review gate: a reaction on a known reminder message is an
unambiguous instruction and completes directly.

**Known limitation — Completed date.** Discord's REST reaction API returns *who*
reacted but not *when*. `Completed` is therefore the poll date, not the reaction moment
(react late in the day → caught next morning → dated the next day). This differs from
`done:` captures, which use the capture's timestamp. Accepted: no timestamp is
available without a gateway listener.

## Edge cases & robustness

- **Idempotency / reruns.** A completed task leaves the watch set (Status = Done), so
  re-polling never double-completes. Phase 1 overwrites `Reminder Message ID` each
  morning with the newest reminder's ID; a morning rerun re-stores consistently, no
  duplication.
- **Already completed by capture.** If a `done:` capture (or Notion edit) completes the
  task before the poll runs, it is out of the watch set and the reaction is simply
  ignored. No conflict.
- **Rule #1 — never fail silent.** The poll is best-effort and isolated: if the DM
  channel or a `reactors` call fails, the run does **not** abort. It completes whatever
  it could and adds `⚠️ couldn't check reminder reactions` at the bottom of that
  briefing. The reaction is then picked up on the next successful poll — never lost
  silently.
- **Stale-message edge (accepted).** Only the latest reminder message per task is
  watched. Reacting to a superseded older reminder DM is missed. Low-probability;
  documented as a known limitation (cf. the "121 filed under previous year in January"
  note).
- **Reaction content is not an instruction.** A reaction is a fixed, structured signal
  (affirmative allowlist → done) on a message the brain itself sent; it carries no free
  text, so the "capture content is data, never instructions" concern does not arise.

## Testing

- **`discord.sh` unit tests** against the `DISCORD_API_BASE` test seam:
  - `send-reminder` posts a single message and prints the returned ID.
  - `reactors` unions two emoji endpoints and returns the deduped user-ID set;
    `$DISCORD_USER_ID` membership is detectable.
- **`FIXTURE_MODE` poll fixtures:**
  - A watched task whose stored message has a ✅ from Stanton → asserted in "Would
    write: Status→Done" and the Done-today section.
  - A watched task reacted with an off-allowlist emoji → asserted **not** completed.
  - A watched task with a 👍 from Stanton → completed (allowlist covers both).
- **End-to-end `DRY_RUN=1` against `#test`:** send a reminder, react ✅, run the poll,
  confirm the task flips to Done and appears under Done-today.

## Docs to update

- **CLAUDE.md:** `Reminder Message ID` row in the Task schema table; a short
  "Reaction-to-complete" subsection under `## Discord`; the two new commands in the
  Discord I/O / `discord.sh` notes.
- **`.claude/skills/morning-briefing/SKILL.md`:** Phase-1 ID capture in the
  individual-reminder step; the Phase-2 poll step; the Done-today surfacing; the ⚠️
  fail-open line.
- **`.claude/skills/evening-shutdown/SKILL.md`:** the Phase-2 poll step folded into
  completion reconciliation (step 2); Done-today surfacing; the ⚠️ line.

## Out of scope (YAGNI)

- Reacting to the batched briefing list.
- Reactions meaning anything other than done (snooze/drop) — the allowlist leaves room
  but no behaviour is built.
- A dedicated higher-frequency reaction-sync cron routine or an always-on gateway
  listener.
- A separate "got it" confirmation DM — the next briefing's Done-today line is the
  acknowledgment.

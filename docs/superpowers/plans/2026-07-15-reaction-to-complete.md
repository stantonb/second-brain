# Reaction-to-complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Stanton mark a Task done by reacting (✅ or 👍) to its individual reminder DM, instead of typing a `done:` capture.

**Architecture:** The morning run stores each reminder DM's message ID on the task (new `Reminder Message ID` property). The morning and evening runs poll that watch set — for each still-open task, they check its stored message for an affirmative reaction from Stanton and mark matches Done. Explicit message-ID→task mapping means no fuzzy matching and no Needs-Review gate. There is no always-on listener; pickup happens at the next run.

**Tech Stack:** Bash (`scripts/discord.sh`, `scripts/notion.sh`), bats + a curl stub for shell tests, Markdown SKILL.md skill instructions executed by Claude, Notion REST + Discord REST, JSON fixtures for `FIXTURE_MODE`.

## Global Constraints

Copied verbatim from `CLAUDE.md`; every task's requirements implicitly include these.

- **Timezone:** all "today"/date logic resolves in **Europe/London**, explicitly — `TODAY=$(TZ=Europe/London date +%F)`. Never rely on system-default time.
- **Rule #1 — never fail silent:** if a service is unreachable, still deliver with whatever succeeded plus an explicit `⚠️ couldn't reach/​check <service>` line.
- **Notion access split:** every exhaustive read and every write goes through `scripts/notion.sh` (`query`, `set-props`) using REST property JSON — never the connector's write tools, never a partial/search read.
- **Discord I/O:** all Discord calls go through `scripts/discord.sh`.
- **Write scope:** the brain writes **only** inside the Second Brain section. CSD EL is READ-ONLY; Habit Tracker and DnD are never read or written.
- **Secrets** (`DISCORD_BOT_TOKEN`, `DISCORD_USER_ID`, `DISCORD_TEST_CHANNEL_ID`, `NOTION_TOKEN`, …) are environment variables only — never commit, print, or log them.
- **Tone:** British English, concise; every line earns its place.
- **Affirmative reaction allowlist:** `✅` (U+2705) and `👍` (U+1F44D). These are the only reactions that complete a task.

---

## File Structure

- `scripts/discord.sh` — **modify.** Add `dm-channel`, `send-reminder`, `reactors`; refactor `send_dm` to reuse the new `dm_channel` helper. Update `usage()` + dispatch.
- `tests/discord/send_react.bats` — **modify.** Add bats coverage for `dm-channel` and `send-reminder`.
- `tests/discord/reactors.bats` — **create.** bats coverage for `reactors`.
- `CLAUDE.md` — **modify.** New Task-schema row; a "Reaction-to-complete" bullet under `## Discord`.
- `tests/fixtures/notion/tasks-reminder-watch.json` — **create.** The reaction-poll watch set for `FIXTURE_MODE`.
- `tests/fixtures/discord/reminder-reactions.json` — **create.** Reactions per reminder message ID for `FIXTURE_MODE`.
- `tests/fixtures/README.md` — **modify.** Two new mapping rows.
- `.claude/skills/morning-briefing/SKILL.md` — **modify.** Phase-1 ID capture in the reminder step; the Phase-2 poll step.
- `.claude/skills/evening-shutdown/SKILL.md` — **modify.** The Phase-2 poll step folded into completion reconciliation.

---

### Task 1: `discord.sh` — `dm-channel` + `send-reminder`

Adds a DM-channel-id helper and a single-message send that **returns the created message ID** (reminder DMs need their ID captured). `send_dm` is refactored to reuse the helper (no behaviour change).

**Files:**
- Modify: `scripts/discord.sh` (add `dm_channel`, `send_reminder`; refactor `send_dm`; update `usage()` + `main` dispatch)
- Test: `tests/discord/send_react.bats`

**Interfaces:**
- Produces (CLI):
  - `discord.sh dm-channel` → prints the DM channel ID for `$DISCORD_USER_ID` (opens/reuses via `POST /users/@me/channels`).
  - `discord.sh send-reminder [channel_id]` → sends the stdin message as a single POST (to `channel_id`, else to the DM channel) and prints the **created message's ID** (`.id`).
- Produces (functions, for bats): `dm_channel`, `send_reminder [channel_id]` (stdin → message text).

- [ ] **Step 1: Write the failing tests**

Add to `tests/discord/send_react.bats`:

```bash
@test "dm_channel opens the DM channel and prints its id" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"DM1"}' > "$CURL_STUB_DIR/1.body"
  export DISCORD_USER_ID='111111111111111111'
  run dm_channel
  [ "$status" -eq 0 ]
  [ "$output" = "DM1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/users/@me/channels')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.recipient_id')" = "111111111111111111" ]
}

@test "send_reminder to a channel posts one message and prints its id" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"MSG777"}' > "$CURL_STUB_DIR/1.body"
  output=$(printf '⏰ Due today: Foo' | send_reminder 555); status=$?
  [ "$status" -eq 0 ]
  [ "$output" = "MSG777" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/555/messages')" = "1" ]
  [ "$(grep -c '/users/@me/channels' "$CURL_STUB_DIR/calls.log")" = "0" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.content')" = "⏰ Due today: Foo" ]
}

@test "send_reminder with no channel opens the DM then posts, printing the id" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"DM1"}'   > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '{"id":"MSG42"}' > "$CURL_STUB_DIR/2.body"
  export DISCORD_USER_ID='111111111111111111'
  output=$(printf 'hi' | send_reminder); status=$?
  [ "$status" -eq 0 ]
  [ "$output" = "MSG42" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/users/@me/channels')" = "1" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/DM1/messages')" = "1" ]
}
```

> Note: `send_reminder` and `send_channel` are already sourced by `setup()`, so these cases pipe stdin straight into the function (matching the existing `send_channel` test) and capture the printed id in `output`; the `dm_channel` test uses `run` since it takes no stdin.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/discord/send_react.bats`
Expected: the three new tests FAIL (`dm_channel: command not found` / `send_reminder: command not found`); the four pre-existing tests still PASS.

- [ ] **Step 3: Implement the helper, the command, and the refactor**

In `scripts/discord.sh`, add `dm_channel` and `send_reminder`, and refactor `send_dm`. Replace the existing `send_dm` block:

```bash
# dm_channel — prints the DM channel id for $DISCORD_USER_ID (opens/reuses it).
dm_channel() {
  discord_api POST '/users/@me/channels' \
    "{\"recipient_id\":\"$DISCORD_USER_ID\"}" | jq -r '.id'
}

# send_dm — stdin → DM to $DISCORD_USER_ID (opens/reuses the DM channel).
send_dm() {
  send_channel "$(dm_channel)"
}

# send_reminder [CHANNEL_ID] — stdin → ONE POST (no chunking); prints the created
# message id. No CHANNEL_ID → the DM channel. Used for individual reminder DMs whose
# id must be stored on the task for reaction-to-complete.
send_reminder() {
  local channel_id=${1:-} content payload
  content=$(cat)
  [[ -n $channel_id ]] || channel_id=$(dm_channel)
  payload=$(printf '%s' "$content" | jq -c -Rs '{content: .}')
  discord_api POST "/channels/$channel_id/messages" "$payload" | jq -r '.id'
}
```

Update `usage()` — add these two lines inside the here-doc:

```
  dm-channel                               print the DM channel id for $DISCORD_USER_ID
  send-reminder [channel_id]               send ONE message (text on stdin); print its id
```

Update the `main` dispatch `case` — add:

```bash
    dm-channel)     : "${DISCORD_USER_ID:?DISCORD_USER_ID must be set}"; dm_channel ;;
    send-reminder)  send_reminder "${1:-}" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/discord/send_react.bats`
Expected: all tests PASS (three new + four pre-existing, including `send_dm opens the DM channel then posts to it`).

- [ ] **Step 5: Commit**

```bash
git add scripts/discord.sh tests/discord/send_react.bats
git commit -m "feat(discord): dm-channel + send-reminder (returns message id)"
```

---

### Task 2: `discord.sh` — `reactors`

Lists the user IDs that reacted to a message with any emoji in a given set (the poll passes the affirmative allowlist). Returns the deduped union across emojis.

**Files:**
- Modify: `scripts/discord.sh` (add `reactors`; update `usage()` + `main` dispatch)
- Test: `tests/discord/reactors.bats` (create)

**Interfaces:**
- Consumes: `discord_api` (existing).
- Produces (CLI): `discord.sh reactors <channel_id> <message_id> [emoji...]` → prints a JSON array of the deduped user IDs who reacted with any listed emoji (default: `✅ 👍`). One `GET …/reactions/{emoji}?limit=100` per emoji.

- [ ] **Step 1: Write the failing test**

Create `tests/discord/reactors.bats`:

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; }
teardown() { teardown_discord; }

@test "reactors unions reactors across the given emojis, deduped" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '[{"id":"U1"},{"id":"U2"}]' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '[{"id":"U2"},{"id":"U3"}]' > "$CURL_STUB_DIR/2.body"
  run reactors 555 1001 ✅ 👍
  [ "$status" -eq 0 ]
  [ "$(jq -c 'sort' <<<"$output")" = '["U1","U2","U3"]' ]
  [ "$(grep -c '%E2%9C%85' "$CURL_STUB_DIR/calls.log")" = "1" ]   # ✅
  [ "$(grep -c '%F0%9F%91%8D' "$CURL_STUB_DIR/calls.log")" = "1" ] # 👍
  [ "$(grep -c '/channels/555/messages/1001/reactions/' "$CURL_STUB_DIR/calls.log")" = "2" ]
}

@test "reactors defaults to the ✅/👍 allowlist when no emoji given" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '[]' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '[]' > "$CURL_STUB_DIR/2.body"
  run reactors 555 1001
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  [ "$(cat "$CURL_STUB_DIR/count")" = "2" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/discord/reactors.bats`
Expected: FAIL (`reactors: command not found`).

- [ ] **Step 3: Implement `reactors`**

In `scripts/discord.sh`, add after `react`:

```bash
# reactors CHANNEL_ID MESSAGE_ID [EMOJI...] — prints a JSON array of the deduped user
# ids that reacted with any listed emoji (default ✅ 👍). One GET per emoji.
reactors() {
  local channel_id=$1 message_id=$2; shift 2
  local emojis=("$@") users='[]' e encoded resp
  (( ${#emojis[@]} )) || emojis=(✅ 👍)
  for e in "${emojis[@]}"; do
    encoded=$(jq -rn --arg x "$e" '$x | @uri')
    resp=$(discord_api GET \
      "/channels/$channel_id/messages/$message_id/reactions/$encoded?limit=100") || return 1
    users=$(jq -s '(.[0] + [.[1][].id]) | unique' <<<"$users$resp")
  done
  printf '%s\n' "$users"
}
```

Update `usage()` — add inside the here-doc:

```
  reactors <channel_id> <message_id> [emoji...]  user-ids that reacted (default ✅ 👍)
```

Update the `main` dispatch `case` — add:

```bash
    reactors)  reactors "${1:?channel_id required}" "${2:?message_id required}" "${@:3}" ;;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/discord/reactors.bats && bats tests/discord/`
Expected: all PASS (new file + the whole discord suite green).

- [ ] **Step 5: Commit**

```bash
git add scripts/discord.sh tests/discord/reactors.bats
git commit -m "feat(discord): reactors — union of affirmative reactors for a message"
```

---

### Task 3: `CLAUDE.md` — schema property + Reaction-to-complete contract

Records the contract both skills follow. Docs-only.

**Files:**
- Modify: `CLAUDE.md` (Task schema table; `## Discord` section)

**Interfaces:**
- Produces: the property name **`Reminder Message ID`** (text) and the affirmative allowlist **✅/👍**, referenced verbatim by Tasks 5 and 6.

- [ ] **Step 1: Add the schema row**

In the Task schema table, immediately after the `Source ID` row, add:

```
| Reminder Message ID | text | Discord message ID of the most recent individual reminder DM for this task; polled by the morning/evening run for an affirmative reaction (✅/👍) from Stanton to auto-complete |
```

- [ ] **Step 2: Add the Reaction-to-complete bullet**

In `## Discord`, immediately after the "Individual reminder notifications" block, add:

```
- **Reaction-to-complete** *(2026-07-15)*: Stanton can mark a task done by reacting to
  its individual reminder DM with an affirmative emoji — the allowlist is **✅ or 👍**.
  When the scheduled morning run sends a reminder DM (above), it stores that DM's message
  ID on the task (`Reminder Message ID`). The **morning and evening** runs then poll the
  watch set — tasks with a non-empty `Reminder Message ID` and Status ∉ {Done, Dropped} —
  and, for each, check that stored message for an affirmative reaction from
  `DISCORD_USER_ID` via `scripts/discord.sh dm-channel` + `reactors`. A match marks the
  task **Done** (Completed + Last Touched = the poll date, Europe/London — Discord's
  reaction API carries no timestamp). The mapping is explicit (message ID → exact task),
  so there is **no** fuzzy match and **no** `Needs Review` gate, unlike a `done:` capture.
  Only individual reminder DMs are reactable; the batched briefing is not. Known limits:
  only the **latest** reminder message per task is watched (a reaction on a superseded
  older DM is missed), and pickup is at the next run, not live. On any reaction-check
  failure the run adds `⚠️ couldn't check reminder reactions` and never fails silent. The
  reminder send uses `scripts/discord.sh send-reminder` (returns the message ID).
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: Reminder Message ID property + reaction-to-complete contract"
```

---

### Task 4: `FIXTURE_MODE` fixtures for the reaction poll

Canned watch set + reactions so the morning/evening poll is testable offline.

**Files:**
- Create: `tests/fixtures/notion/tasks-reminder-watch.json`
- Create: `tests/fixtures/discord/reminder-reactions.json`
- Modify: `tests/fixtures/README.md`

**Interfaces:**
- Produces: two fixtures + a documented mapping consumed by the FIXTURE_MODE poll in Tasks 5 and 6. The reactions fixture uses the sentinel user id **`STANTON`** to stand in for `$DISCORD_USER_ID`.
- Expected poll outcome from these fixtures: `9001` (✅ STANTON) → Done; `9002` (👍 STANTON) → Done; `9003` (🎉 STANTON, off-allowlist) → **not** done; `9004` (✅ but not STANTON) → **not** done.

- [ ] **Step 1: Create the watch-set fixture**

`tests/fixtures/notion/tasks-reminder-watch.json`:

```json
[
  { "id": "task-9001", "name": "Send Q3 numbers to Priya", "status": "Next",        "reminder_message_id": "9001" },
  { "id": "task-9002", "name": "Book venue deposit",        "status": "In progress", "reminder_message_id": "9002" },
  { "id": "task-9003", "name": "Reply to landlord",         "status": "Next",        "reminder_message_id": "9003" },
  { "id": "task-9004", "name": "Renew car insurance",       "status": "Waiting",     "reminder_message_id": "9004" }
]
```

- [ ] **Step 2: Create the reactions fixture**

`tests/fixtures/discord/reminder-reactions.json` (keyed by message id → emoji → reactor user ids):

```json
{
  "9001": { "✅": ["STANTON"] },
  "9002": { "👍": ["STANTON"] },
  "9003": { "🎉": ["STANTON"] },
  "9004": { "✅": ["SOMEONE_ELSE"] }
}
```

- [ ] **Step 3: Document the mapping**

In `tests/fixtures/README.md`, add to the mapping table:

```
| Reaction-poll watch set (Tasks with a non-empty `Reminder Message ID`, Status ∉ Done/Dropped) | `notion/tasks-reminder-watch.json` |
| Reactions on reminder DMs — `discord.sh reactors` | `discord/reminder-reactions.json` (keyed by message id → emoji → reactor user ids; the `STANTON` sentinel = `$DISCORD_USER_ID`; affirmative allowlist ✅/👍) |
```

- [ ] **Step 4: Validate the JSON**

Run: `jq empty tests/fixtures/notion/tasks-reminder-watch.json && jq empty tests/fixtures/discord/reminder-reactions.json && echo OK`
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/notion/tasks-reminder-watch.json tests/fixtures/discord/reminder-reactions.json tests/fixtures/README.md
git commit -m "test(fixtures): reaction-poll watch set + reminder reactions"
```

---

### Task 5: Morning skill — record reminder ID (Phase 1) + poll reactions (Phase 2)

Two edits to the morning skill: capture each reminder DM's ID onto its task (Phase 1), and poll the watch set to complete reacted tasks (Phase 2). Verified by a `FIXTURE_MODE` run.

**Files:**
- Modify: `.claude/skills/morning-briefing/SKILL.md`

**Interfaces:**
- Consumes: `discord.sh send-reminder` (Task 1), `discord.sh dm-channel` + `reactors` (Tasks 1–2), `Reminder Message ID` property + ✅/👍 allowlist (Task 3), fixtures (Task 4).

- [ ] **Step 1: Add the Phase-2 poll step**

In `.claude/skills/morning-briefing/SKILL.md`, insert a new step immediately after step 1 (Triage captures), before step 2 (121 ingestion):

````
1b. **Poll reminder reactions → complete tasks** (both scheduled and on-demand runs;
   `CLAUDE.md → Discord → Reaction-to-complete`). Marks tasks Stanton completed by reacting
   to a reminder DM, so they drop off the rolling list and don't re-nag. Run this **before**
   the Tasks step (4) and the reminder step (10).
   - **Watch set:** `./scripts/notion.sh query <tasks-ds>` (data-source id in CLAUDE.md) with

     ```json
     {"and":[
       {"property":"Reminder Message ID","rich_text":{"is_not_empty":true}},
       {"property":"Status","select":{"does_not_equal":"Done"}},
       {"property":"Status","select":{"does_not_equal":"Dropped"}}
     ]}
     ```

   - **Channel:** production → `CH=$(./scripts/discord.sh dm-channel)`; `DRY_RUN=1` →
     `CH=$DISCORD_TEST_CHANNEL_ID` (reminders were sent there); `FIXTURE_MODE=1` → read
     `tests/fixtures/discord/reminder-reactions.json` and the watch set from
     `tests/fixtures/notion/tasks-reminder-watch.json`, treating the `STANTON` sentinel as
     `$DISCORD_USER_ID` — no Discord/Notion calls.
   - For each watched task, `AFFIRMED=$(./scripts/discord.sh reactors "$CH" "$MSGID" ✅ 👍)`.
     If `$DISCORD_USER_ID` is in that array, mark the task **Done** via
     `./scripts/notion.sh set-props <page-id>`:

     ```json
     {"Status":{"select":{"name":"Done"}},
      "Completed":{"date":{"start":"$TODAY"}},
      "Last Touched":{"date":{"start":"$TODAY"}}}
     ```

   - The morning format has **no** Done-today section, so reaction-completed tasks simply
     leave the rolling list — no separate line (evening reports same-day ones).
   - **Rule #1:** if `dm-channel` or any `reactors` call fails, do **not** abort — finish the
     run and add `⚠️ couldn't check reminder reactions` at the bottom of the briefing. In
     `FIXTURE_MODE`, list each completion `set-props` under "Would write:".
````

- [ ] **Step 2: Add Phase-1 ID capture to the reminder step**

In step 10 (Individual reminder notifications), replace the three delivery bullets
(`Production: … send-dm`, `DRY_RUN=1: … send-channel`, `FIXTURE_MODE=1: … "Would send:"`)
with:

````
     - Production: `MID=$(printf '%s' "$MSG" | ./scripts/discord.sh send-reminder)`.
     - `DRY_RUN=1`: `MID=$(printf '%s' "$MSG" | ./scripts/discord.sh send-reminder "$DISCORD_TEST_CHANNEL_ID")`.
     - `FIXTURE_MODE=1`: no send — list each message under "Would send:" (no message id).
     - After a real send (production or `DRY_RUN`), store the returned id on the task so the
       reaction poll (step 1b) can watch it — one `set-props` per reminder:

       ```json
       {"Reminder Message ID":{"rich_text":[{"text":{"content":"$MID"}}]}}
       ```

       In `FIXTURE_MODE`, list this `set-props` under "Would write:" instead.
````

- [ ] **Step 3: Verify in FIXTURE_MODE**

Run the morning skill in `FIXTURE_MODE=1` (per the skill's Modes table). Confirm in the printed "Would write:" list:
- `task-9001` and `task-9002` → Status→Done (✅ and 👍 from STANTON).
- `task-9003` (🎉, off-allowlist) and `task-9004` (✅ but not STANTON) → **no** completion.
- No `⚠️ couldn't check reminder reactions` line (fixtures resolve cleanly).

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/morning-briefing/SKILL.md
git commit -m "feat(morning): store reminder message id + poll reactions to complete tasks"
```

---

### Task 6: Evening skill — poll reactions in completion reconciliation

Evening never sends reminders (no Phase 1); it only polls (Phase 2). Reaction-completed tasks get `Completed = TODAY`, so the existing step 2 lists them under "Done today" automatically — tagged so the source is clear.

**Files:**
- Modify: `.claude/skills/evening-shutdown/SKILL.md`

**Interfaces:**
- Consumes: `discord.sh dm-channel` + `reactors` (Tasks 1–2), `Reminder Message ID` + ✅/👍 allowlist (Task 3), fixtures (Task 4).

- [ ] **Step 1: Add the poll step before completion reconciliation**

In `.claude/skills/evening-shutdown/SKILL.md`, insert a new step immediately after step 1 (Triage captures), before step 2 (Reconcile completions):

````
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
````

- [ ] **Step 2: Tag reaction completions in the Done-today line**

In step 2 (Reconcile completions), append to its description:

```
   Tasks completed by the reaction poll (step 1b) have Completed = TODAY, so they appear in
   "Done today" automatically; suffix those lines " — by reaction" so the source is clear.
```

- [ ] **Step 3: Verify in FIXTURE_MODE**

Run the evening skill in `FIXTURE_MODE=1`. Confirm:
- `task-9001` and `task-9002` → Status→Done in "Would write:", and appear under "Done today" suffixed " — by reaction".
- `task-9003` and `task-9004` → not completed.
- No `⚠️ couldn't check reminder reactions` line.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/evening-shutdown/SKILL.md
git commit -m "feat(evening): poll reminder reactions in completion reconciliation"
```

---

### Task 7: End-to-end verification against `#test` (DRY_RUN)

Proves the full loop against live Discord + Notion without touching production delivery. Manual (requires Stanton to react). No code.

**Files:** none (verification only).

- [ ] **Step 1: Send a reminder and store its ID**

With a real test task that is due today or overdue (create one if needed), run the morning skill with `DRY_RUN=1`. Confirm: the individual reminder DM lands in `#test`, and the task's `Reminder Message ID` in Notion is now that message's ID.

- [ ] **Step 2: React**

In `#test`, react to that reminder message with ✅ (repeat separately with 👍 on a second run to confirm both).

- [ ] **Step 3: Poll**

Run the evening skill (or the morning skill again) with `DRY_RUN=1`. Confirm: the task flips to `Status = Done`, `Completed = TODAY` (Europe/London), and — for the evening run — appears under "Done today — by reaction".

- [ ] **Step 4: Negative + idempotency checks**

- React to another `#test` reminder with an off-allowlist emoji (e.g. 🎉) → confirm the task is **not** completed on the next poll.
- Re-run the poll after a completion → confirm the already-Done task is not re-processed (it has left the watch set) and nothing double-writes.

- [ ] **Step 5: Record the result**

Note the verification outcome in the PR description / commit message when finishing the branch. No commit if nothing changed.

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- Reactable surface = individual reminder DMs → Task 5 step 2 (send-reminder + ID capture); batched list untouched.
- Pickup at next run (morning + evening) → Tasks 5 & 6 poll steps.
- Affirmative allowlist ✅/👍 → Global Constraints + Tasks 2, 3; negative case tested in Tasks 4–6.
- Approach A explicit mapping / new `Reminder Message ID` property → Task 3 (schema) + Tasks 5–6 (query/write).
- `send-reminder` (routes DM/#test, returns id) → Task 1. `reactors` → Task 2. `dm-channel` (needed to read DM reactions) → Task 1.
- Phase 1 (record on send, morning-only) → Task 5 step 2, all three modes. Phase 2 (poll & complete) → Tasks 5 step 1 + 6 step 1.
- Completed = poll date (no reaction timestamp) → Tasks 5/6 set-props; noted in Task 3 contract.
- Done-today surfacing + "— by reaction" tag → Task 6 step 2; morning has no Done section (documented) → Task 5 step 1.
- Rule #1 fail-open `⚠️ couldn't check reminder reactions` → Tasks 5 & 6.
- Idempotency (Done leaves watch set; morning overwrites id on rerun) → watch-set filter excludes Done/Dropped (Tasks 5/6); reminder re-fire guard unchanged; verified Task 7 step 4.
- Testing: discord.sh bats → Tasks 1–2; FIXTURE_MODE poll fixtures (✅, 👍, off-allowlist, other-user) → Tasks 4–6; e2e DRY_RUN → Task 7.
- Docs: CLAUDE.md → Task 3; both SKILL.md → Tasks 5–6; fixtures README → Task 4.
- Out-of-scope items (batched-list reactions, snooze/drop reactions, dedicated cron/gateway, confirmation DM) → not planned, matching the spec.

**2. Placeholder scan** — no TBD/TODO; every code/edit step shows the actual content. `$MSGID`/`$MID`/`$TODAY`/`<page-id>`/`<tasks-ds>` are runtime shell variables and documented data-source ids, not placeholders.

**3. Type/name consistency** — `dm_channel`/`dm-channel`, `send_reminder`/`send-reminder`, `reactors`, and the property name `Reminder Message ID` are used identically across Tasks 1–6. The allowlist is `✅ 👍` everywhere. The `STANTON` sentinel is defined in Task 4 and consumed in Tasks 5–6.

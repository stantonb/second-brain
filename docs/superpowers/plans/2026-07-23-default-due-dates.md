# Default Due Dates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every brain-created task gets a `Due` date — defaulting to add-date + 7 days when none is stated — plus a scheduled-morning sweep for dateless tasks and a one-off staggered backfill, so every open task eventually fires an individual ⏰ reminder DM.

**Architecture:** This repo's behaviour *is* its markdown contracts: CLAUDE.md holds the rules, `.claude/skills/*/SKILL.md` hold the run procedures, and `FIXTURE_MODE=1` skill runs against `tests/fixtures/**` are the behaviour tests. The change is therefore contract edits (default-due rule at the three creation points + a sweep step in the morning skill), fixture/bats updates to exercise it, and one live `notion.sh` migration.

**Tech Stack:** Markdown contracts executed by Claude, Bash (`scripts/notion.sh` REST wrapper), bats + curl stub for `scripts/discord.sh`, JSON fixtures.

**Spec:** `docs/superpowers/specs/2026-07-23-default-due-date-design.md` — read it before starting.

## Global Constraints

Copied from CLAUDE.md and the spec; every task's requirements implicitly include these.

- **Timezone:** all date logic resolves in **Europe/London**, explicitly — `TODAY=$(TZ=Europe/London date +%F)`. Date arithmetic: `date -v+7d +%F` on macOS, `date -d '+7 days' +%F` on Linux cloud runs.
- **Rule #1 — never fail silent:** a failed service still yields a delivered briefing plus an explicit `⚠️` line.
- **Notion access split:** every exhaustive read and every write goes through `scripts/notion.sh` (`query`, `set-props`) with REST property JSON. The Tasks data-source id (bare, no `collection://` prefix) is `01e1c068-5703-423a-b910-f4bd5644e4ab`.
- **The default never overwrites an existing `Due`**, and the sweep/backfill **never update `Last Touched`** — a datestamp is not a touch; aging and the 30-day cull must stay honest.
- **Sweep gating:** scheduled morning run only — never on an on-demand brief-me. Idempotent on a rerun (nothing dateless remains).
- **Canonical strings** (must match everywhere): briefing section `**📆 Defaulted due**   (dateless tasks stamped +7d)`; failure line `⚠️ couldn't default due dates`; CLAUDE.md subsection title `### Default due date *(2026-07-23)*`.
- **Secrets** are environment variables only — never commit, print, or log them.
- **Tone:** British English, concise; every line earns its place.

---

## File Structure

- `CLAUDE.md` — **modify.** Default-due rule in triage rules 4 and 7; 121 `Due` bullet; new `### Default due date` subsection after the aging rules; `📆` section in the Morning format.
- `.claude/skills/morning-briefing/SKILL.md` — **modify.** New step 2b (the sweep); `Due` default noted in step 2's 121 create.
- `.claude/skills/evening-shutdown/SKILL.md` — **verify only.** Triage defers to CLAUDE.md; confirm no restated "Due blank".
- `tests/fixtures/discord/captures-page-2.json` — **modify.** Add a dateless actionable capture.
- `tests/discord/fetch_captures.bats` — **modify.** Length/cursor assertions track the new fixture message.
- `tests/fixtures/README.md` — **modify.** Mapping row for the sweep query.
- One-off live backfill — **no repo file**; executed once via `scripts/notion.sh`.

---

### Task 1: CLAUDE.md — the default-due contract

All five contract edits land together: the rule statement, the two triage-rule hooks, the 121 hook, and the briefing-format section. A reviewer can hold the whole contract change in one diff.

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Produces (for Tasks 2–4): the subsection `### Default due date *(2026-07-23)*` (referenced by the morning skill's step 2b), the briefing section header `**📆 Defaulted due**`, and the ⚠️ line `⚠️ couldn't default due dates`.

- [ ] **Step 1: Read `CLAUDE.md`**, then make edits 1a–1e below (exact old → new text).

**Edit 1a — triage rule 4 (`waiting:`).** Replace:

```markdown
4. `waiting: <person> <thing>` → Task with Status `Waiting`, Waiting-on = person.
```

with:

```markdown
4. `waiting: <person> <thing>` → Task with Status `Waiting`, Waiting-on = person. No
   stated or inferable due date → `Due` = capture date + 7 (the default-due rule) — the
   eventual reminder doubles as a chase-up nudge.
```

**Edit 1b — triage rule 7 (actionable).** Replace:

```markdown
7. Anything actionable → Task: infer Domain, Due, Priority; Status `Inbox`, promoted to
   `Next` if clearly actionable now. Source = `Discord capture`, Source ID = message ID.
```

with:

```markdown
7. Anything actionable → Task: infer Domain, Due, Priority; Status `Inbox`, promoted to
   `Next` if clearly actionable now. No due date stated or inferable → `Due` = the
   capture's date + 7 (the default-due rule). Source = `Discord capture`,
   Source ID = message ID.
```

**Edit 1c — new subsection after the aging rules.** Immediately after the line:

```markdown
- **Pinned** tasks are exempt from both; **snoozed** tasks don't age until they wake.
```

(and before `## Triage intent rules`) insert:

```markdown

### Default due date *(2026-07-23)*

No brain-created task is left dateless — a task with no `Due` never fires an individual
reminder DM, so dateless tasks sat on the rolling list indefinitely. A stated or
inferable date always wins; the default **never overwrites** an existing `Due`.

- **Captures** (rules 4 and 7): `Due` = the capture message's **timestamp date + 7 days**
  (Europe/London — the same anchor as relative dates; late triage must not shift it).
- **121 ingestion**: no stated deadline → `Due` = the **ingestion run date + 7 days** —
  not the 121 page's date, so a carried-over action from an old page never lands
  pre-overdue. The page date still anchors *stated* deadlines, unchanged.
- **Sweep (backstop)**: the **scheduled** morning run (never on-demand) stamps
  `Due = TODAY + 7` on every open task (Status ∉ {Done, Dropped}, snoozed included)
  whose `Due` is empty — this catches tasks added by hand in Notion. It never updates
  `Last Touched`, and it is idempotent (a rerun finds nothing dateless). Stamped tasks
  are surfaced in that briefing's `📆 Defaulted due` section; on any sweep failure the
  briefing carries `⚠️ couldn't default due dates` (rule #1) and the next morning's
  sweep catches what was missed.
```

**Edit 1d — 121 ingestion `Due` bullet.** In `## 121 action-point ingestion`, replace:

```markdown
  - `Due` = set **only** if the action states a deadline, resolved from the **121 page's
    own date** (parsed from its `DDMMYYYY` title), Europe/London — e.g. "by Friday" on a
    `07072026` page → `2026-07-10`. No stated deadline → `Due` blank.
```

with:

```markdown
  - `Due` = a stated deadline, resolved from the **121 page's own date** (parsed from
    its `DDMMYYYY` title), Europe/London — e.g. "by Friday" on a `07072026` page →
    `2026-07-10`. No stated deadline → `Due` = the ingestion run date + 7 days (the
    default-due rule, 2026-07-23).
```

**Edit 1e — Morning briefing format.** In `## Briefing formats → ### Morning`, after:

```markdown
**🗂 New from 1:1s**   (ingested action points — triage into the rolling list)
- {task} — 1:1 with {person} ({DD Mon})
```

and before `**❓ Decisions needed**`, insert:

```markdown
**📆 Defaulted due**   (dateless tasks stamped +7d)
- {task} → due {Ddd D Mon}
```

- [ ] **Step 2: Verify the edits are complete and consistent**

Run: `grep -c "default-due rule\|Default due date\|📆 Defaulted due" CLAUDE.md`
Expected: `6` (rule 4, rule 7, subsection title, 121 bullet, subsection body's 📆 mention, Morning format). Also run `grep -n "Due\` blank" CLAUDE.md` — expected: no matches.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat(tasks): default-due rule in the contract — +7d on all creation paths, morning sweep"
```

---

### Task 2: morning-briefing skill — the sweep step; evening/weekly verified untouched

**Files:**
- Modify: `.claude/skills/morning-briefing/SKILL.md`
- Verify (no expected change): `.claude/skills/evening-shutdown/SKILL.md`, `.claude/skills/weekly-review/SKILL.md`

**Interfaces:**
- Consumes: `### Default due date *(2026-07-23)*` (CLAUDE.md, Task 1), section header `**📆 Defaulted due**`, ⚠️ line `⚠️ couldn't default due dates`.
- Produces: SKILL.md step `2b` — the sweep — whose `FIXTURE_MODE` source is `tests/fixtures/notion/tasks.json` (Task 3 relies on this mapping).

- [ ] **Step 1: Read `.claude/skills/morning-briefing/SKILL.md`**, then make edits 2a–2b.

**Edit 2a — note the default in step 2's 121 create.** Replace:

```markdown
   a deduped `Inbox`/`Work` Task per **new** action (`Source ID` `121:{person}#{bullet-key}`,
   content-based, dedupe by querying Tasks for `Source ID starts_with "121:"`). Collect the
   newly-created actions for the
```

with:

```markdown
   a deduped `Inbox`/`Work` Task per **new** action (`Source ID` `121:{person}#{bullet-key}`,
   content-based, dedupe by querying Tasks for `Source ID starts_with "121:"`; `Due` = a
   stated deadline anchored to the page date, else the run date + 7 — the default-due
   rule). Collect the newly-created actions for the
```

**Edit 2b — insert the sweep as step 2b.** Immediately after step 2's closing line:

```markdown
   page blocks, and existing Source IDs from the fixtures (`tests/fixtures/README.md`
   mapping) and list each `create` under "Would write:".
```

insert:

```markdown
2b. **Default-due sweep** (scheduled run only — skip entirely on an on-demand run;
   safe on a rerun, which finds nothing left dateless). Per `CLAUDE.md → ## Task
   schema → ### Default due date`: one `notion.sh query` on the Tasks data source for
   dateless open tasks —

   ```json
   {"and":[
     {"property":"Status","select":{"does_not_equal":"Done"}},
     {"property":"Status","select":{"does_not_equal":"Dropped"}},
     {"property":"Due","date":{"is_empty":true}}
   ]}
   ```

   For each result (snoozed tasks included — a date must be waiting when they wake):
   `DUE=$(TZ=Europe/London date -v+7d +%F)` (`date -d '+7 days' +%F` on Linux cloud
   runs), then `./scripts/notion.sh set-props <page-id>` with

   ```json
   {"Due":{"date":{"start":"$DUE"}}}
   ```

   **Never update `Last Touched`** — a datestamp is not a touch; aging must stay
   honest. Collect the stamped names + dates for the `📆 Defaulted due` section (step
   9's compose; omit the section when the sweep stamped nothing). This step runs
   before step 4 so the rolling list shows the fresh dates. In `FIXTURE_MODE` the
   query reads `tests/fixtures/notion/tasks.json` (rows with `"due": null`) and each
   `set-props` is listed under "Would write:". **Rule #1:** on a query or write
   failure don't abort — stamp what you can and add `⚠️ couldn't default due dates`
   at the bottom of the briefing; the next morning's sweep catches the rest.
```

- [ ] **Step 2: Verify the evening and weekly skills need no change**

Run: `grep -n -i "due.*blank\|blank.*due" .claude/skills/evening-shutdown/SKILL.md .claude/skills/weekly-review/SKILL.md`
Expected: no matches — both skills defer task creation to CLAUDE.md's triage rules, so the capture default lands there automatically. (Evening rollover's "Due is left unchanged" line is correct and stays.) If a restated "Due blank" does turn up, align it with the default-due rule in the same style as edit 2a.

- [ ] **Step 3: Verify the sweep reference chain**

Run: `grep -n "Default due date\|📆 Defaulted due\|couldn't default due dates" .claude/skills/morning-briefing/SKILL.md`
Expected: 2b's reference to the CLAUDE.md subsection, the 📆 collect note, and the ⚠️ line — all present, spelled exactly as in Global Constraints.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/morning-briefing/SKILL.md
git commit -m "feat(morning): default-due sweep step 2b + 121 create default"
```

---

### Task 3: fixtures + bats — exercise the default and the sweep

The existing fixtures already carry three dateless open tasks (`Book dentist`, `Chase legal re DPA`, `Write blog post on routines` in `notion/tasks.json`) — they become the sweep case as-is. What's missing is a dateless **actionable** capture (rule-7 default) — the existing `waiting:` capture covers rule 4. Adding a message to `captures-page-2.json` shifts `fetch_captures.bats`'s length and cursor assertions, so they move together.

**Files:**
- Modify: `tests/fixtures/discord/captures-page-2.json`
- Modify: `tests/discord/fetch_captures.bats`
- Modify: `tests/fixtures/README.md`

**Interfaces:**
- Consumes: step 2b's fixture mapping (Task 2); the fixture capture's timestamp date `2026-07-06` → expected default `Due` `2026-07-13`.

- [ ] **Step 1: Add the dateless actionable capture**

Replace the full contents of `tests/fixtures/discord/captures-page-2.json` with:

```json
[
  {
    "id": "1391402271633244163",
    "content": "Sort out the loft ladder",
    "author": { "id": "111111111111111111", "username": "stanton", "bot": false },
    "timestamp": "2026-07-06T11:00:00.000000+00:00"
  },
  {
    "id": "1391402271633244162",
    "content": "waiting: Sam contract review for the DPA",
    "author": { "id": "111111111111111111", "username": "stanton", "bot": false },
    "timestamp": "2026-07-06T10:00:00.000000+00:00"
  }
]
```

(Newest-first within the page, matching `captures-page-1.json`; `fetch_captures` sorts each page ascending and cursors on the max id.)

- [ ] **Step 2: Update the bats assertions to track the new fixture**

In `tests/discord/fetch_captures.bats`, replace:

```bash
  [ "$(jq 'length' <<<"$output")" = "3" ]
  [ "$(jq -r '.[0].id' <<<"$output")" = "1391402271633244160" ]
  [ "$(jq -r '.[2].id' <<<"$output")" = "1391402271633244162" ]
```

with:

```bash
  [ "$(jq 'length' <<<"$output")" = "4" ]
  [ "$(jq -r '.[0].id' <<<"$output")" = "1391402271633244160" ]
  [ "$(jq -r '.[3].id' <<<"$output")" = "1391402271633244163" ]
```

and replace:

```bash
  [ "$(sed -n '3p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=1391402271633244162')" = "1" ]
```

with:

```bash
  [ "$(sed -n '3p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=1391402271633244163')" = "1" ]
```

Run: `bats tests/discord/fetch_captures.bats`
Expected: PASS (fixture and assertions changed together; if either step was missed the pagination test FAILs — that is the check).

- [ ] **Step 3: Run the full bats suite**

Run: `bats tests/discord/ tests/notion/ tests/gh/`
Expected: all PASS — nothing else reads the captures fixture.

- [ ] **Step 4: Add the fixture-mapping row**

In `tests/fixtures/README.md`, after the row:

```markdown
| Notion Tasks DB rolling-list query | `notion/tasks.json` |
```

insert:

```markdown
| Default-due sweep query (dateless open tasks) | `notion/tasks.json` (rows with `"due": null`) |
```

- [ ] **Step 5: `FIXTURE_MODE` behaviour verification (the feature's test)**

Invoke the `morning-briefing` skill with `FIXTURE_MODE=1` (scheduled shape: no `ON_DEMAND`) and check the printed output. With `TODAY` = the real run date and `SWEEP_DUE` = `TODAY + 7`:

1. "Would write:" includes a Task **create** for `Sort out the loft ladder` with `Due = 2026-07-13` (capture timestamp 2026-07-06 + 7 — rule-7 default).
2. "Would write:" includes a Task **create** for the `waiting:` capture (Waiting-on = Sam) with `Due = 2026-07-13` (rule-4 default).
3. "Would write:" includes exactly **three** sweep `set-props` — `Book dentist`, `Chase legal re DPA`, `Write blog post on routines` — each `Due = $SWEEP_DUE` and **no `Last Touched`** in the payload.
4. The briefing shows `**📆 Defaulted due**` listing those three tasks.
5. `Q3 roadmap draft` and `Renew passport` (dated fixtures) get **no** sweep write.
6. The 121-ingestion fixtures' created tasks carry a `Due` (stated deadline or run date + 7) — none blank.

Expected: all six hold. If any fails, fix the contract/skill text from Tasks 1–2 (the fixtures are the spec's test harness), re-run, then continue.

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures/discord/captures-page-2.json tests/discord/fetch_captures.bats tests/fixtures/README.md
git commit -m "test(fixtures): dateless capture + sweep mapping; bats tracks 4th capture"
```

---

### Task 4: One-off staggered backfill (live migration — run once)

**Sequencing constraint (from the spec) — read carefully, this is the one thing most likely to go wrong.** The sweep (step 2b) is code-independent of this backfill: the moment step 2b can execute in production, the *first* scheduled morning run stamps every dateless open task with a single `TODAY + 7`, so they all fire ⏰ DMs on the same morning — defeating the whole point of the random(1–14) stagger. Approval ≠ merge ≠ deploy: this backfill must complete **before the sweep can first execute in production**. Because it depends on nothing in the diff, the safest order is to **run it before merging** (or in the same session immediately after), then confirm Step 4's invariant (no dateless open task remains) before the next scheduled 06:45 run. Call this out in the PR description so the operator cannot miss it. No repo change; nothing to commit.

**Files:** none (live Notion mutation via `scripts/notion.sh`).

**Interfaces:**
- Consumes: the Tasks data-source id `01e1c068-5703-423a-b910-f4bd5644e4ab`; the dateless-open-tasks filter from Task 2.

- [ ] **Step 1: Load env and verify auth**

```bash
set -a; source ~/.config/second-brain/env; set +a
./scripts/notion.sh whoami >/dev/null && echo OK
```

Expected: `OK`. (Never print the token or the whoami body.)

- [ ] **Step 2: List the dateless open tasks**

```bash
DL=$(mktemp)
./scripts/notion.sh query 01e1c068-5703-423a-b910-f4bd5644e4ab '{"and":[
  {"property":"Status","select":{"does_not_equal":"Done"}},
  {"property":"Status","select":{"does_not_equal":"Dropped"}},
  {"property":"Due","date":{"is_empty":true}}
]}' > "$DL"
jq -r '.[] | [.id, (.properties.Name.title[0].plain_text // "?"), (.properties.Status.select.name // "?")] | @tsv' "$DL"
```

Expected: roughly the seven undated rolling-list tasks (as of 2026-07-22) plus any dateless `Inbox`/snoozed tasks. Sanity-check the names before writing — if the list looks wrong (empty, or hundreds of rows), stop and investigate before mutating.

- [ ] **Step 3: Stamp each with `Due = TODAY + random(1–14)`**

```bash
while IFS=$'\t' read -r id name; do
  days=$((RANDOM % 14 + 1))
  due=$(TZ=Europe/London date -v+${days}d +%F)   # Linux: date -d "+${days} days" +%F
  ./scripts/notion.sh set-props "$id" "{\"Due\":{\"date\":{\"start\":\"$due\"}}}" >/dev/null \
    && printf '%s\t%s\n' "$name" "$due" || printf '%s\tFAILED\n' "$name"
done < <(jq -r '.[] | [.id, (.properties.Name.title[0].plain_text // "?")] | @tsv' "$DL")
```

Expected: one `task-name<TAB>date` line per task, dates scattered across the next 1–14 days, no `FAILED` lines. The payload sets **only `Due`** — `Last Touched` stays untouched. Retry any `FAILED` row once; if it still fails, report it to Stanton rather than leaving it silent.

- [ ] **Step 4: Verify the invariant now holds**

Re-run the Step 2 query. Expected: `[]` — no dateless open task remains. Then report the full task → date table to Stanton.

- [ ] **Step 5 (optional, from the spec): `DRY_RUN` end-to-end**

`DRY_RUN=1` morning run: briefing lands in `#test`; the sweep finds nothing dateless (Step 4's invariant), so no `📆 Defaulted due` section appears and a rerun stamps nothing.

---

## Self-Review (completed at write time)

- **Spec coverage:** rule 4/7 defaults → Task 1a/1b; sweep behaviour + surfacing + ⚠️ → 1c/1e + 2b; 121 default → 1d + 2a; Last-Touched/idempotency constraints → Global Constraints + 2b + backfill Step 3; fixtures (creation default, sweep, not-re-stamped) → Task 3 Step 5; backfill incl. sequencing → Task 4; evening no-change verification → Task 2 Step 2; optional DRY_RUN e2e → Task 4 Step 5. No gaps found.
- **Placeholder scan:** none — every edit carries its exact text, every command its expected output.
- **Consistency:** section header, ⚠️ line, and subsection title match across Tasks 1–3 and Global Constraints; the sweep filter JSON in 2b matches Task 4's backfill query; data-source id is the bare UUID everywhere.

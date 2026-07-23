# Default due dates — design

*Date: 2026-07-23. Feature: every task the brain creates gets a Due date — defaulting to
one week from when it was added — so every open task eventually surfaces as an
individual ⏰ reminder DM instead of sitting silently on the rolling list.*

## Problem

Individual reminder DMs fire only for tasks that are overdue, due today, or waking from
snooze. A task captured without a stated or inferable deadline gets a blank `Due` and
therefore **never** triggers one — it sits on the rolling list indefinitely (as of
2026-07-22, seven of the eleven rolling-list tasks were dateless). Stanton wants a
safety net: "make the default TODO time on an item 1 week from when it gets added, so
eventually everything ends up as an individual message."

## Decisions (from brainstorming)

1. **Scope: all creation paths.** Rule-7 actionable captures, rule-4 `waiting:`
   captures, and 121-ingested actions all get the default. No brain-created task ever
   exists without a `Due`. For `waiting:` tasks the eventual reminder doubles as a
   chase-up nudge.
2. **Approach: creation-point defaults + a morning sweep backstop.** The creation paths
   stamp the correctly-anchored date immediately; the scheduled morning run additionally
   sweeps any open task with a blank `Due` (catches tasks added by hand in Notion, and
   any future ingestion path that forgets). Nothing can stay dateless for more than a
   day.
3. **Backfill: one-off, staggered.** Existing open dateless tasks get
   `Due = today + random(1–14) days`, independently per task, so the accumulated backlog
   does not fire as one wall of overdue DMs (Stanton's call: "random for each task
   between 1 and 14 days so all don't fire at once").
4. **Anchors.** Captures anchor to the **message's timestamp date** + 7 — consistent
   with the existing relative-date rule (a capture triaged a day late must not shift).
   121 ingestion anchors to the **ingestion run date** + 7, deliberately **not** the 121
   page's own date: a carried-over action filed from a weeks-old page would otherwise
   land already-overdue and blast a reminder the next morning. (The page date remains
   the anchor for *stated* deadlines, unchanged.)

## Behaviour

### The default rule

When a task is created and no due date is stated or inferable:

| Path | Default `Due` |
|---|---|
| Rule-7 actionable capture | capture message's timestamp date + 7 days (Europe/London) |
| Rule-4 `waiting:` capture | capture message's timestamp date + 7 days |
| 121 action-point ingestion | ingestion run date + 7 days |

An explicit or inferable date always wins; the default **never overwrites** an existing
`Due`. Multi-intent messages need no special casing — each split line triages
independently and any task it creates gets the same treatment.

### The sweep (backstop)

A step in the **scheduled** morning run only (same gating as 121 ingestion — never on an
on-demand brief-me; drift ≤ 24 h is accepted):

1. Query Tasks for Status ∉ {`Done`, `Dropped`} **and** `Due` empty (snoozed tasks
   included — they need a date waiting for them when they wake).
2. For each: `Due = TODAY + 7` via `notion.sh set-props`.
3. **`Last Touched` is not updated** — a datestamp is not a touch; aging flags and the
   30-day cull must stay honest.

Idempotent by construction: after a successful sweep no dateless open task remains, so a
rerun stamps nothing. In `FIXTURE_MODE` the writes are listed under "Would write:"; in
`DRY_RUN` they are real (the sweep is idempotent, like capture triage).

### Surfacing

Sweep-stamped tasks appear in that morning's briefing — no silent mutations:

```text
**📆 Defaulted due**   (dateless tasks stamped +7d)
- {task} → due {Ddd D Mon}
```

Section omitted when the sweep stamped nothing (the steady state). Creation-path
defaults need no extra surfacing — the date shows in the rolling list / New-from-1:1s
lines as usual.

### What does not change

- **Reminder DMs**: wording, buckets, and precedence are untouched — defaulted dates
  simply flow into the existing Overdue / Due-today logic. A task snoozed past its
  defaulted date wakes via the existing precedence (due-based wording).
- **Evening rollover** still never modifies `Due` — overdue is information.
- **Aging rules** (14-day ⏳, 30-day cull, Pinned/snoozed exemptions) are unchanged.
- A defaulted date is stored identically to an explicit one — no marker property
  (YAGNI; the 📆 line at stamp time is the disclosure).

## One-off backfill (live migration)

Run **once**, manually, immediately after this lands — and **before the next scheduled
morning run**, otherwise the sweep stamps the whole backlog `today + 7` un-staggered and
they all fire on the same day:

1. `notion.sh query` Tasks: Status ∉ {`Done`, `Dropped`}, `Due` empty — full pagination.
   This catches dateless `Inbox` and snoozed tasks too, not just the rolling list.
2. Per task: `Due = TODAY + random(1–14) days` (independent draw per task),
   `notion.sh set-props`. `Last Touched` untouched.
3. Report the task → assigned-date table in the session; no Journal entry (it is a
   console migration, not a run).

## Edge cases & robustness

- **Rule #1 — never fail silent.** If the sweep's query or a write fails, the run does
  not abort: it stamps what it can and adds `⚠️ couldn't default due dates` at the
  bottom of the briefing. Unstamped tasks are caught by the next morning's sweep.
- **Rerun of the scheduled morning run**: the sweep finds nothing dateless (stamped
  earlier that day) — no double-stamping, consistent with reminder no-re-fire rules.
- **Late triage**: a capture processed a day late still anchors to its message
  timestamp, per the existing relative-dates rule.
- **Consequence, accepted**: within ~2 weeks every open task has a date, and anything
  untouched past its date fires a ⏰ Overdue DM every scheduled morning until completed
  (✅ reaction), snoozed, or dropped. That is the point of the feature; the pressure
  valves already exist.

## Testing

- **Fixtures** (`FIXTURE_MODE=1` morning run):
  - A dateless actionable capture in `tests/fixtures/discord/` → asserted "Would write:"
    a Task with `Due` = message date + 7.
  - A dateless open task in `tests/fixtures/notion/tasks.json` → asserted swept
    (`Due = TODAY + 7` under "Would write:") and listed under 📆 Defaulted due.
  - Existing dated fixtures → asserted **not** re-stamped.
- **`DRY_RUN=1` end-to-end** (optional): live sweep against real Notion, briefing to
  `#test`, confirm the 📆 section and that a rerun stamps nothing.

## Docs to update

- **CLAUDE.md**: default-due rule added to triage rules 4 and 7; 121 section's `Due`
  bullet ("No stated deadline → `Due` blank" → run date + 7); a short "Default due
  date" subsection near the aging rules covering the sweep; the 📆 section added to the
  Morning briefing format.
- **`.claude/skills/morning-briefing/SKILL.md`**: the sweep step (before the
  rolling-list read, so the briefing shows fresh dates); 121 step note; 📆 surfacing;
  the ⚠️ fail-open line.
- **`.claude/skills/evening-shutdown/SKILL.md`**: expected no change (triage defers to
  CLAUDE.md) — verify no restated "Due blank" during implementation.

## Out of scope (YAGNI)

- A property marking a date as defaulted vs explicit.
- Escalation / deduplication of repeated daily overdue DMs.
- An evening-run sweep (morning-only keeps drift ≤ 24 h and the evening run lean).
- Re-anchoring or re-randomising dates after the backfill.
- Any change to rollover, aging, or cull mechanics.

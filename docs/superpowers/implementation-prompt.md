# Handoff prompt — build the second brain from the approved spec

Start a fresh Claude Code session in `~/Projects.Git/second-brain` and paste everything
below the line.

---

Read `docs/superpowers/specs/2026-07-06-second-brain-design.md` in full before doing
anything else. It is the **approved design** for my second brain — brainstorming is
complete; do not redesign it or reopen decisions recorded there.

Your job: use the **superpowers:writing-plans** skill to turn the spec into a sequence of
small implementation plans, then execute them **strictly in order** using the
superpowers plan-execution workflow, stopping at every checkpoint marked below.

## Stage sequence (one plan per stage; each must be verified working before the next starts)

**Stage 0 — Access & setup verification.**
Walk me through, with exact instructions: creating the private Discord server, the bot
(token, Message Content privileged intent, read/send/reaction permissions), the
`#capture` and `#test` channels; generating a fine-grained GitHub PAT scoped to the repo
allowlist; connecting the Notion, Gmail, and Google Calendar connectors at claude.ai —
including **testing whether my work Google account (Simply Business) can connect at
all**; if it's blocked, apply the spec's calendar-sharing fallback and record that
work-email triage moves to the roadmap. Deliverable: `scripts/check-env.sh` written and
passing locally.

**Stage 1 — Repo skeleton.**
`CLAUDE.md` schema file (identity; Notion workspace map with the `CSD EL` read-only rule
and `Habit Tracker`/`DND` hard exclusions using **real page IDs discovered via the Notion
connector**; triage intent rules; briefing formats; GitHub repo allowlist; Europe/London
timezone rule), `scripts/discord.sh` (paginated fetch, send with 2000-char splitting,
✅ reactions, 429/Retry-After handling), and test fixtures for Discord/Notion/GitHub data.
Use TDD for script logic.

**Stage 2 — Notion setup.**
Create the "Second Brain" section and its databases exactly as specced (Tasks, Journal,
Capture Log, Reading list, Brag doc — all properties, all views). Record database IDs in
`CLAUDE.md`. Verify by round-tripping a test task through the connector.

**Stage 3 — Morning briefing.** ✋ CHECKPOINT
Build the skill; dry-run against fixtures; then a live dry-run posting to `#test`; then
create the routine (daily 06:45 Europe/London, connectors: Notion + Google only, custom
network access allowing discord.com, env vars set). Verify **two consecutive real
morning deliveries**, then stop and wait for me to confirm the briefings look right
before starting Stage 4.

**Stage 4 — Evening shutdown.** ✋ CHECKPOINT
Same pattern: skill → fixture dry-run → `#test` → routine at 21:00 → verified real
deliveries → my confirmation.

**Stage 5 — Weekly review.** ✋ CHECKPOINT
Same pattern, Sunday 17:00, including the 14-run Journal self-check and brag doc append
(reading recently updated `CSD EL` sub-pages, read-only).

**Stages 6–11 — Phase 2 items**, one plan each, in the spec's committed order (on-demand
briefing API trigger, dead-man's switch, weekly Notion backup, `meeting:` pipeline,
recurring tasks, time-block proposals). Do not start these until the core has run
reliably for at least a week — if we're inside that week, stop after Stage 5 and tell me.

## Rules

- The spec is the source of truth. If reality contradicts it (connector unavailable, API
  changed, permission blocked), **stop and ask me** rather than silently deviating; then
  record the agreed change in the spec with a dated note.
- Secrets live only in the cloud environment's env vars and my local shell — never
  committed, never echoed into logs.
- Steps only I can do (web UI clicks, OAuth consents, token generation) must appear in
  plans as explicit user-action steps with exact instructions; wait for me to confirm
  each before continuing.
- Never write to Notion outside the Second Brain section; never read `Habit Tracker` or
  `DND`.
- Every stage ends with a verification step that shows me real output (superpowers
  verification-before-completion applies — evidence before claims).
- Commit after each completed stage with a clear message.

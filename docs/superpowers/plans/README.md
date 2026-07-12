# Plans — execution order

Source spec: `docs/superpowers/specs/2026-07-06-second-brain-design.md`.
One plan per stage. Each stage must be **verified working** (evidence shown to Stanton)
before the next starts. ✋ = hard checkpoint: stop and wait for Stanton's explicit
confirmation.

## Core (Stages 0–5) — COMPLETE

| Order | Plan | Gate |
|---|---|---|
| 0 | `2026-07-06-stage-0-access-setup.md` | check-env.sh passing locally |
| 1 | `2026-07-06-stage-1-repo-skeleton.md` | bats suite green + CLAUDE.md confirmed |
| 2 | `2026-07-06-stage-2-notion-setup.md` | test-task round-trip shown |
| — | `2026-07-07-stage-2-addendum-notion-sh.md` | notion.sh REST reads/writes (TDD) |
| 3 | `2026-07-06-stage-3-morning-briefing.md` | ✋ two consecutive real 06:45 deliveries + Stanton's OK |
| 4 | `2026-07-06-stage-4-evening-shutdown.md` | ✋ verified real 21:00 deliveries + Stanton's OK |
| 5 | `2026-07-06-stage-5-weekly-review.md` | ✋ verified real Sunday 17:00 delivery + Stanton's OK |

Core closed 2026-07-12 (commit `b7d2633`): morning 06:45, evening 21:00, weekly Sunday
17:00 all live and verified in production.

## Phase 2 (Stages 6–11) — PLANNED 2026-07-12, execution gated

Planning gate opened early at Stanton's direction (spec note 2026-07-12). Plans are
written; **execution of each stage still waits for Stanton's explicit go**, stage by
stage, per each plan's ✋ checkpoint. The reliability bar is unchanged: **Sunday 19 Jul
2026's weekly self-check clean (or every gap explained)** before any Phase 2 code ships
to production. Same fixture → DRY_RUN → production contract, TDD for script changes,
USER-ACTION stops for anything only Stanton can do on the personal claude.ai account.

| Order | Plan | Spec item | Gate |
|---|---|---|---|
| 6 | `2026-07-12-stage-6-on-demand-briefing.md` | 1 | ✋ a real phone-fired "brief me now" delivers a DM without disturbing the scheduled run + Stanton's OK |
| 7 | `2026-07-12-stage-7-dead-mans-switch.md` | 2 | ✋ each routine's healthchecks.io check goes green on a real production ping + Stanton's OK |
| 8 | `2026-07-12-stage-8-weekly-backup.md` | 3 | ✋ a real weekly run commits an updated backup to `main` (verified on `origin/main`) + Stanton's OK |
| 9 | `2026-07-12-stage-9-meeting-pipeline.md` | 4 | ✋ a real `meeting:` capture → correct structured note + action tasks, dedupes on rerun + Stanton's OK |
| 10 | `2026-07-12-stage-10-recurring-tasks.md` | 5 | ✋ a real recurring task spawns exactly one correct next instance (none on rerun) + Stanton's OK |
| 11 | `2026-07-12-stage-11-time-block-proposals.md` | 6 | ✋ the ⏱ time-block section is accurate and never writes the calendar + Stanton's OK |

Surface facts verified before writing (spec note 2026-07-12): routines expose an
on-demand **fire** endpoint + a "Run now" button (Stage 6 reads the exact URL/token off
Stanton's Routines UI); cloud runs default to `claude/`-prefixed-branch pushes and
**Stanton chose direct-to-`main`** for the backup (Stage 8 enables the unrestricted-pushes
toggle).

## Still unplanned (deliberately)

- **Stage 12 — Phase 2 item 7: 121 action-point ingestion** (actions from `DDMMYYYY - 121`
  notes under **read-only** CSD EL into Tasks). Reuses Stage 9's extraction convention;
  planned when Stanton opens it.
- **Phase 2 item 8 — Siri voice capture** is already **live** (phone-side webhook +
  Shortcut, `docs/setup.md` §7) — no build stage, no gate.
- The Roadmap items in the spec's final section remain possible later phases.

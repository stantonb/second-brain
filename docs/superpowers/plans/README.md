# Plans — execution order

Source spec: `docs/superpowers/specs/2026-07-06-second-brain-design.md`.
One plan per stage. Each stage must be **verified working** (evidence shown to Stanton)
before the next starts. ✋ = hard checkpoint: stop and wait for Stanton's explicit
confirmation.

| Order | Plan | Gate |
|---|---|---|
| 0 | `2026-07-06-stage-0-access-setup.md` | check-env.sh passing locally |
| 1 | `2026-07-06-stage-1-repo-skeleton.md` | bats suite green + CLAUDE.md confirmed |
| 2 | `2026-07-06-stage-2-notion-setup.md` | test-task round-trip shown |
| 3 | `2026-07-06-stage-3-morning-briefing.md` | ✋ two consecutive real 06:45 deliveries + Stanton's OK |
| 4 | `2026-07-06-stage-4-evening-shutdown.md` | ✋ verified real 21:00 deliveries + Stanton's OK |
| 5 | `2026-07-06-stage-5-weekly-review.md` | ✋ verified real Sunday 17:00 delivery + Stanton's OK |

## Phase 2 queue (Stages 6–11 — NOT yet planned, deliberately)

Per the spec and the handoff prompt, Phase 2 may not start until the core (Stages 3–5)
has run reliably for **at least one week**. Their plans are written when that gate opens,
against what the week reveals (routine trigger surface, failure modes). Committed order:

6. On-demand briefing (`/fire` API trigger + iOS Shortcut)
7. Dead-man's switch (healthchecks.io pings per routine)
8. Weekly Notion backup (export to `backups/`, commit)
9. `meeting:` capture pipeline
10. Recurring tasks
11. Time-block proposals

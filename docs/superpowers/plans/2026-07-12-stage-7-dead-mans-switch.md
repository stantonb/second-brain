# Stage 7 — Dead-Man's Switch (healthchecks.io) Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** Every production routine run ends by pinging a per-routine healthchecks.io URL, so a run that dies — or never starts — is caught by a missed-ping alert the same day, not only by Sunday's self-check.

**Architecture:** A tiny TDD'd `scripts/healthcheck.sh` wraps the ping. It is observability-only: a ping failure is **non-fatal** (always exits 0) so healthchecks.io being down can never fail the brain; a blank URL is a silent no-op. Each of the three skills pings its own URL (`HEALTHCHECK_URL_MORNING/EVENING/WEEKLY`) as the very last action, **production only** (fixture and dry-run never touch the dead-man's timer — else a test run would mask a missing scheduled run).

**Tech Stack:** bash, curl, bats (reusing the `tests/*/stubs` pattern), healthchecks.io, claude.ai cloud env vars.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md` (Phase 2 item 2). Reality contradicts it → STOP and ask Stanton; record the agreed change with a dated note.
- Secrets/URLs only in cloud env vars + Stanton's local shell. The ping URLs are semi-secret (they carry a UUID) — never committed, printed, or logged.
- Notion writes only inside Second Brain; `Habit Tracker`/`DND` never read; `CSD EL` read-only.
- Rule #1 — never fail silent: the dead-man's switch is *itself* a fail-loud mechanism; it must never make the run fail. A ping error is logged and swallowed.
- **The ping fires only in production** (not FIXTURE_MODE, not DRY_RUN) and only as the last action, after delivery + journalling.
- TDD for the new script; `check-env.sh` additions are verified by running it (project precedent — check-env has no unit tests, it hits live services).
- Anything only Stanton can do on the personal account (healthchecks.io account, cloud env) is a **USER-ACTION** with exact instructions, then STOP.
- ✋ **CHECKPOINT:** each routine's healthchecks.io check goes green on a real production ping, then STOP for Stanton's confirmation before Stage 8.
- Commit after each task.

**Prerequisite:** Core complete (Stages 0–5); Phase 2 planning gate open. **Execution waits for Stanton's explicit go and the reliability bar.**

---

### Task 1: TDD `scripts/healthcheck.sh`

**Files:**
- Create: `tests/healthcheck/stubs/curl`
- Create: `tests/healthcheck/test_helper.bash`
- Create: `tests/healthcheck/healthcheck.bats`
- Create: `scripts/healthcheck.sh`

**Interfaces:**
- Produces: `hc_ping URL [SUFFIX]` (always returns 0); CLI `healthcheck.sh {ping|start|fail} <url>`. Consumed by all three skills.

- [ ] **Step 1: Write `tests/healthcheck/stubs/curl`** — a minimal stub that records argv and can simulate curl failure (the shared discord/notion stub always succeeds, so it can't exercise the non-fatal path):

```bash
#!/usr/bin/env bash
# Test stub for curl in healthcheck tests. Records argv to calls.log and exits with the
# code in $CURL_STUB_DIR/exit (default 0), so a test can simulate a ping failure.
printf '%s\n' "$*" >> "$CURL_STUB_DIR/calls.log"
exit "$(cat "$CURL_STUB_DIR/exit" 2>/dev/null || echo 0)"
```

Then `chmod +x tests/healthcheck/stubs/curl`.

- [ ] **Step 2: Write `tests/healthcheck/test_helper.bash`**

```bash
# Shared setup for healthcheck.sh bats tests.
setup_healthcheck() {
  CURL_STUB_DIR=$(mktemp -d)
  export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  source "$BATS_TEST_DIRNAME/../../scripts/healthcheck.sh"
}

teardown_healthcheck() {
  rm -rf "$CURL_STUB_DIR"
}
```

- [ ] **Step 3: Write the failing tests — `tests/healthcheck/healthcheck.bats`**

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_healthcheck; }
teardown() { teardown_healthcheck; }

@test "ping curls the URL and returns 0" {
  run hc_ping "https://hc.example/abc"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'https://hc.example/abc' "$CURL_STUB_DIR/calls.log")" = "1" ]
}

@test "a failing ping is non-fatal (still returns 0, logs a warning)" {
  echo 7 > "$CURL_STUB_DIR/exit"          # curl exit 7 = couldn't connect
  run hc_ping "https://hc.example/abc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"non-fatal"* ]]
}

@test "an empty URL is a silent no-op (no curl call, returns 0)" {
  run hc_ping ""
  [ "$status" -eq 0 ]
  [ ! -f "$CURL_STUB_DIR/calls.log" ]
}

@test "start appends /start to the URL" {
  run hc_ping "https://hc.example/abc" /start
  [ "$status" -eq 0 ]
  [ "$(grep -c 'https://hc.example/abc/start' "$CURL_STUB_DIR/calls.log")" = "1" ]
}

@test "fail appends /fail to the URL" {
  run hc_ping "https://hc.example/abc" /fail
  [ "$status" -eq 0 ]
  [ "$(grep -c 'https://hc.example/abc/fail' "$CURL_STUB_DIR/calls.log")" = "1" ]
}

@test "CLI: unknown command prints usage and exits 2" {
  run bash scripts/healthcheck.sh bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
```

- [ ] **Step 4: Run to verify failure** — `bats tests/healthcheck/` → `No such file` (healthcheck.sh missing).

- [ ] **Step 5: Implement `scripts/healthcheck.sh`**

```bash
#!/usr/bin/env bash
# healthcheck.sh — dead-man's-switch pings to healthchecks.io.
#
# Observability only. A ping failure (healthchecks.io down, no network) must NEVER fail
# the brain's run, so every ping returns 0. The failure mode we actually want to detect
# — a routine that dies, or never starts, before it can ping — shows up as a *missing*
# ping, which healthchecks.io turns into an alert. A blank/unset URL is a silent no-op,
# so local dry-runs and unconfigured environments don't error.
#
# Commands (URL is the full healthchecks.io check URL):
#   ping  <url>   signal success at the end of a completed run
#   start <url>   signal run start (<url>/start) — optional, measures duration
#   fail  <url>   signal an explicit failure (<url>/fail)
#
# Env: HC_TIMEOUT (per-attempt curl timeout in seconds, default 10).

HC_TIMEOUT="${HC_TIMEOUT:-10}"

# hc_ping URL [SUFFIX] — POST the check URL (optionally /start or /fail). Always 0.
hc_ping() {
  local url=$1 suffix=${2:-}
  [[ -z $url ]] && return 0
  if ! curl -fsS -m "$HC_TIMEOUT" --retry 3 -o /dev/null "${url}${suffix}"; then
    echo "healthcheck: ping failed (non-fatal): ${url}${suffix}" >&2
  fi
  return 0
}

usage() {
  cat >&2 <<'EOF'
usage: healthcheck.sh <command> <url>
  ping  <url>   signal a successful run
  start <url>   signal run start (<url>/start)
  fail  <url>   signal a failure (<url>/fail)
EOF
  exit 2
}

main() {
  local cmd=${1:-} url=${2:-}
  case $cmd in
    ping)  hc_ping "$url" ;;
    start) hc_ping "$url" /start ;;
    fail)  hc_ping "$url" /fail ;;
    *)     usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  main "$@"
fi
```

- [ ] **Step 6: Run to verify pass** — `chmod +x scripts/healthcheck.sh && bats tests/healthcheck/` → `6 tests, 0 failures`. Then `bats -r tests/` → all green (24 existing + 6 new = 30).
- [ ] **Step 7: Commit**

```bash
git add scripts/healthcheck.sh tests/healthcheck
git commit -m "feat: healthcheck.sh — non-fatal dead-man's-switch pings (TDD)"
```

---

### Task 2: Wire the ping into all three skills

**Files:**
- Modify: `.claude/skills/morning-briefing/SKILL.md`
- Modify: `.claude/skills/evening-shutdown/SKILL.md`
- Modify: `.claude/skills/weekly-review/SKILL.md`
- Modify: `CLAUDE.md` (Secrets section)

**Interfaces:**
- Consumes: `scripts/healthcheck.sh` from Task 1; the mode contract.
- Produces: a production-only completion ping per routine.

- [ ] **Step 1: `.claude/skills/morning-briefing/SKILL.md`** — append this step after step 8 (`Compose, deliver, journal`):

```markdown
9. **Signal completion (dead-man's switch).** As the very last action, **production
   only** (skip in FIXTURE_MODE and DRY_RUN): `./scripts/healthcheck.sh ping
   "$HEALTHCHECK_URL_MORNING"`. This never fails the run — an unset URL is a no-op and a
   ping error is logged, not fatal. A run that died before here sends no ping, which is
   exactly the alert.
```

- [ ] **Step 2: `.claude/skills/evening-shutdown/SKILL.md`** — append after step 6 (`Compose, deliver, journal`):

```markdown
7. **Signal completion (dead-man's switch).** As the very last action, **production
   only** (skip in FIXTURE_MODE and DRY_RUN): `./scripts/healthcheck.sh ping
   "$HEALTHCHECK_URL_EVENING"`. Never fails the run; a missing ping is the alert.
```

- [ ] **Step 3: `.claude/skills/weekly-review/SKILL.md`** — append after step 5 (`Deliver + journal`):

```markdown
6. **Signal completion (dead-man's switch).** As the very last action, **production
   only** (skip in FIXTURE_MODE and DRY_RUN): `./scripts/healthcheck.sh ping
   "$HEALTHCHECK_URL_WEEKLY"`. Never fails the run; a missing ping is the alert.
```

- [ ] **Step 4: `CLAUDE.md` → `## Secrets`.** Append after the existing env-var line:

```markdown
Dead-man's-switch ping URLs (optional but recommended, cloud only):
`HEALTHCHECK_URL_MORNING`, `HEALTHCHECK_URL_EVENING`, `HEALTHCHECK_URL_WEEKLY` — each
carries a UUID; treat as secret. An unset URL disables that routine's ping (no error).
```

- [ ] **Step 5: Commit**

```bash
git add .claude/skills CLAUDE.md
git commit -m "feat: production-only healthcheck ping at end of each routine"
```

---

### Task 3: check-env.sh + setup runbook

**Files:**
- Modify: `scripts/check-env.sh` (optional Healthchecks section — never fails, never pings)
- Modify: `docs/setup.md` (new `## 9. Dead-man's switch (healthchecks.io)`; §6 cloud env-var list gains the three URLs)

- [ ] **Step 1: `scripts/check-env.sh`** — insert this block immediately before the final `echo` / summary (after the Notion section). It reports presence only and **does not ping** (a ping would register a spurious check-in):

```bash
echo "Healthchecks (optional — configured in the cloud environment):"
for var in HEALTHCHECK_URL_MORNING HEALTHCHECK_URL_EVENING HEALTHCHECK_URL_WEEKLY; do
  if [[ -n "${!var:-}" ]]; then note "$var is set"; else note "$var not set here (set it in the cloud environment)"; fi
done
```

- [ ] **Step 2: Verify check-env still passes** — `bash -c 'source ~/.config/second-brain/env; ./scripts/check-env.sh'` → the three Healthchecks lines appear as ℹ️ and the final tally is unchanged (still `16 passed, 0 failed` locally, since these are `note` lines that don't count).

- [ ] **Step 3: Write `docs/setup.md` §9** with exactly this content:

````markdown
## 9. Dead-man's switch (healthchecks.io)

Each production run pings a per-routine check; a missed ping alerts you the same day.

1. <https://healthchecks.io> → sign up (free tier is plenty) → create a project.
2. Create **three** checks, each with **Schedule = Cron/Simple** matching its routine and
   a grace period that covers the run's stagger + duration:
   - `second-brain-morning` — period **1 day**, grace **1 hour** (run is ~06:45).
   - `second-brain-evening` — period **1 day**, grace **1 hour** (run is ~21:00).
   - `second-brain-weekly` — period **7 days**, grace **3 hours** (run is Sun ~17:00).
3. For each check, copy its **ping URL** (`https://hc-ping.com/<uuid>`) into the cloud
   environment as `HEALTHCHECK_URL_MORNING` / `_EVENING` / `_WEEKLY`. Optionally add them
   to `~/.config/second-brain/env` too (only used if a routine is run locally).
4. In healthchecks.io → **Integrations**, add an **Email** (and/or push) notification so a
   missed ping reaches you.
5. The ping fires only on production runs — fixture and dry-run modes never touch the
   timer, so testing can't mask a missing scheduled run.
````

- [ ] **Step 4: `docs/setup.md` §6** — extend the "Environment variables" bullet to note the three optional `HEALTHCHECK_URL_*` values alongside the six required secrets.

- [ ] **Step 5: Commit**

```bash
git add scripts/check-env.sh docs/setup.md
git commit -m "docs: healthchecks.io setup (§9) + check-env presence check"
```

---

### Task 4: USER-ACTION — create the checks & wire the cloud environment

**Files:** none (personal-account UI).

- [ ] **Step 1: USER ACTION — Stanton** completes `docs/setup.md` §9 steps 1–4: creates the healthchecks.io project + three checks, sets each period/grace, adds the three `HEALTHCHECK_URL_*` values to **the cloud environment** (claude.ai → Claude Code → this repo's environment), and configures an email/push notification. **STOP and wait for confirmation.**
- [ ] **Step 2: Push all commits to `main`** so the routines (which clone the remote) pick up the new skill steps and `healthcheck.sh`.

---

### Task 5: ✋ CHECKPOINT — real pings land

**Files:** none.

- [ ] **Step 1: Trigger one manual production run of `morning-briefing`** (Run now). Verify in healthchecks.io that `second-brain-morning` flips to **green / "up"** with a recent ping, and that the run's DM + Journal still landed (the ping must be additive, not disruptive). Repeat for `evening-shutdown` and `weekly-review` (a mid-week weekly run is fine — the self-check reports a partial week honestly, as in Stage 5).
- [ ] **Step 2:** Confirm the alert path: temporarily lower one check's grace or use healthchecks.io's own "this check is down" preview to confirm Stanton actually receives the email/push. (Do **not** skip a real scheduled run to test it.) Restore the grace afterwards.
- [ ] **Step 3: STOP.** Ask Stanton explicitly: "Dead-man's switch is live — each routine pings, and a miss alerts you. Happy to close Stage 7? Stage 8 (weekly backup) starts only on your word." Wait for confirmation.
- [ ] **Step 4: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 7 — dead-man's switch live, pings verified" --allow-empty
```

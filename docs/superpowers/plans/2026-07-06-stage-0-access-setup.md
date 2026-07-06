# Stage 0 — Access & Setup Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** Every credential and connector the second brain needs exists and is proven live by a passing `scripts/check-env.sh`.

**Architecture:** A human runbook (`docs/setup.md`) covering all web-UI/OAuth steps, plus a bash validator (`scripts/check-env.sh`) that checks env vars and live Discord/GitHub connectivity without ever printing a secret. Notion access is via the claude.ai connector, so it is verified in-session, not from bash.

**Tech Stack:** bash, curl, jq, gh CLI, Discord REST API v10, GitHub REST API.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md`. If reality contradicts it → STOP and ask Stanton; record the agreed change in the spec with a dated note.
- Secrets live only in cloud env vars and Stanton's local shell (`~/.config/second-brain/env`). Never committed, never echoed into logs or tool output.
- Never write to Notion outside the "Second Brain" section; never read/write `Habit Tracker` or `DND`; `CSD EL` is read-only.
- All date logic explicitly Europe/London.
- User-action steps (web UI, OAuth, tokens): give exact instructions, then STOP and wait for Stanton's confirmation before continuing.
- Every stage ends with verification showing real output — evidence before claims.
- Commit after each task; stage ends with a clear stage-completion commit.

---

### Task 1: Write the setup runbook (`docs/setup.md`)

**Files:**
- Create: `docs/setup.md`

**Interfaces:**
- Produces: the numbered sections (§1 Discord, §2 GitHub PAT, §3 connectors, §4 secrets, §5 validate, §6 cloud env) that Tasks 2–5 and the Stage 3 plan reference.

- [ ] **Step 1: Write `docs/setup.md` with exactly this content**

````markdown
# Setup runbook

Everything a human must click to stand up the second brain. Machine-side validation:
`scripts/check-env.sh`. Secrets go in `~/.config/second-brain/env` (§4) — never in this repo.

## 1. Discord server, channels, bot

### 1.1 Server + channels
1. Discord app → **+** (Add a Server) → **Create My Own** → **For me and my friends** →
   name: `Second Brain` → Create.
2. Create two text channels: right-click the server name → **Create Channel** → Text →
   `capture`, then again → `test`.
3. Enable Developer Mode: **User Settings → Advanced → Developer Mode** ON.
4. Right-click **#capture** → **Copy Channel ID** → this is `DISCORD_CAPTURE_CHANNEL_ID`.
5. Right-click **#test** → **Copy Channel ID** → `DISCORD_TEST_CHANNEL_ID`.
6. Right-click your own name in the member list → **Copy User ID** → `DISCORD_USER_ID`.

### 1.2 Bot application
1. <https://discord.com/developers/applications> → **New Application** → name
   `second-brain` → Create.
2. Sidebar → **Bot**:
   - **Reset Token** → copy the token → `DISCORD_BOT_TOKEN`. It is shown once — store it
     in §4's file immediately. Never paste it into chat, logs, or the repo.
   - **Privileged Gateway Intents** → toggle **MESSAGE CONTENT INTENT** ON → Save.
3. Sidebar → **OAuth2** → **URL Generator**:
   - Scopes: `bot`.
   - Bot Permissions: **View Channels**, **Send Messages**, **Read Message History**,
     **Add Reactions**.
   - Copy the generated URL, open it in a browser, choose the **Second Brain** server,
     **Authorise**.
4. Confirm in Discord: the bot appears in the member list and can see #capture and #test.

## 2. GitHub fine-grained PAT

1. Decide the **repo allowlist** — the exact repos the morning briefing watches for PRs/CI.
   These go in `CLAUDE.md → ## GitHub repo allowlist` (Stage 1) and the PAT is scoped to match.
2. <https://github.com/settings/personal-access-tokens/new>:
   - Token name: `second-brain`. Expiration: 90 days (set a renewal reminder).
   - Resource owner: the owner of the allowlist repos. **Note:** repos owned by an
     organisation (e.g. `simplybusiness`) require that org to permit fine-grained PATs —
     if the org isn't offered as resource owner or the token is rejected, that's an IT
     conversation; until resolved, keep only personal repos in the allowlist.
   - Repository access: **Only select repositories** → pick exactly the allowlist repos.
   - Repository permissions: **Pull requests: Read-only**, **Contents: Read-only**,
     **Actions: Read-only** (CI status). Metadata: Read-only is added automatically.
3. **Generate token** → copy → `GH_TOKEN` (store per §4).

## 3. claude.ai connectors

1. <https://claude.ai> → **Settings → Connectors**:
   - **Notion** → Connect → in the OAuth screen grant access to the pages the brain
     needs: `CSD EL` and (once it exists, Stage 2) `Second Brain`. Do **not** grant
     `Habit Tracker` or `DND` — they are hard-excluded by design.
   - **Gmail** → Connect with the **personal** Google account.
   - **Google Calendar** → Connect with the **personal** Google account.
2. **Work-account test (setup step zero from the spec):** attempt to connect Gmail /
   Google Calendar with `stanton.borthwick@simplybusiness.co.uk`. If Google shows
   "app blocked", "needs admin approval", or the grant silently fails → the work
   connector is blocked. Apply the fallback:
   - In the **work** Google Calendar → Settings → your calendar → **Share with specific
     people or groups** → add the personal address with **"See all event details"**.
     If org policy only allows free/busy sharing, accept that — busy blocks still shape
     the day.
   - Record in the spec with a dated note: work Google connector blocked; work-email
     triage moves to the roadmap (it is already roadmap item 7).
3. **Local Notion access for Claude Code** (needed in Stages 1–2 to discover page IDs and
   create databases): open a Claude Code session and run `/mcp`. If no Notion tools are
   listed, add the official Notion MCP server locally:
   `claude mcp add --transport http notion https://mcp.notion.com/mcp`
   then authenticate via `/mcp` (OAuth into the same workspace, same page grants).

## 4. Local secrets

```sh
mkdir -p ~/.config/second-brain
cat > ~/.config/second-brain/env <<'EOF'
export DISCORD_BOT_TOKEN='...'
export DISCORD_USER_ID='...'
export DISCORD_CAPTURE_CHANNEL_ID='...'
export DISCORD_TEST_CHANNEL_ID='...'
export GH_TOKEN='...'
EOF
chmod 600 ~/.config/second-brain/env
```

Load on demand with `source ~/.config/second-brain/env`. Never commit this file, never
echo these values.

## 5. Validate

```sh
source ~/.config/second-brain/env
./scripts/check-env.sh
```

Every line must be ✅ before Stage 1 starts.

## 6. Cloud environment (configured in Stage 3)

At claude.ai → Claude Code → this repo's cloud environment:
- Network access: **Custom** → default allowlist **plus `discord.com`**.
- Environment variables: the five from §4.
- Connectors enabled for routines: **Notion, Gmail, Google Calendar only** — remove all others.
Exact steps live in the Stage 3 plan.
````

- [ ] **Step 2: Commit**

```bash
git add docs/setup.md
git commit -m "docs: add human setup runbook (Discord, PAT, connectors, secrets)"
```

---

### Task 2: Write `scripts/check-env.sh` and smoke-test it without secrets

**Files:**
- Create: `scripts/check-env.sh`

**Interfaces:**
- Consumes: env vars `DISCORD_BOT_TOKEN`, `DISCORD_USER_ID`, `DISCORD_CAPTURE_CHANNEL_ID`, `DISCORD_TEST_CHANNEL_ID`, `GH_TOKEN`; optionally `CLAUDE.md`'s `## GitHub repo allowlist` section (bullets formatted `- owner/repo` — Stage 1 must keep that format).
- Produces: exit 0 iff all checks pass; one ✅/❌ line per check; never prints secret values.

- [ ] **Step 1: Write `scripts/check-env.sh` with exactly this content**

```bash
#!/usr/bin/env bash
# check-env.sh — validate env vars + live connectivity before enabling any routine.
#
# Usage:
#   source ~/.config/second-brain/env
#   ./scripts/check-env.sh
#
# Prints one line per check; exits non-zero if anything failed.
# NEVER prints secret values.
set -uo pipefail

PASS=0 FAIL=0
ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '  ℹ️  %s\n' "$1"; }

API="https://discord.com/api/v10"

# dcode URL [extra curl args...] → prints HTTP status code, body discarded.
dcode() {
  curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bot ${DISCORD_BOT_TOKEN:-}" "$@"
}

echo "Env vars:"
for var in DISCORD_BOT_TOKEN DISCORD_USER_ID DISCORD_CAPTURE_CHANNEL_ID DISCORD_TEST_CHANNEL_ID GH_TOKEN; do
  if [[ -n "${!var:-}" ]]; then ok "$var is set"; else bad "$var is missing"; fi
done

echo "Discord:"
if [[ -n "${DISCORD_BOT_TOKEN:-}" ]]; then
  code=$(dcode "$API/users/@me")
  if [[ $code == 200 ]]; then ok "bot token valid (GET /users/@me → 200)"; else bad "bot auth failed (GET /users/@me → $code)"; fi
  for pair in "capture:${DISCORD_CAPTURE_CHANNEL_ID:-}" "test:${DISCORD_TEST_CHANNEL_ID:-}"; do
    name=${pair%%:*} id=${pair#*:}
    if [[ -n $id ]]; then
      code=$(dcode "$API/channels/$id")
      if [[ $code == 200 ]]; then
        ok "#$name channel visible to bot (→ 200)"
      else
        bad "#$name channel not visible (→ $code — bot invited with View Channels?)"
      fi
    fi
  done
  if [[ -n "${DISCORD_USER_ID:-}" ]]; then
    code=$(dcode "$API/users/@me/channels" -X POST -H 'Content-Type: application/json' \
      -d "{\"recipient_id\":\"${DISCORD_USER_ID}\"}")
    if [[ $code == 200 ]]; then ok "DM channel opens (POST /users/@me/channels → 200)"; else bad "DM channel failed (→ $code)"; fi
  fi
else
  note "skipping Discord API checks (no DISCORD_BOT_TOKEN)"
fi

echo "GitHub:"
if [[ -n "${GH_TOKEN:-}" ]]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user)
  if [[ $code == 200 ]]; then ok "GH_TOKEN valid (GET /user → 200)"; else bad "GH_TOKEN rejected (GET /user → $code)"; fi
  if [[ -f CLAUDE.md ]]; then
    repos=$(awk '/^## GitHub repo allowlist/{f=1;next} /^## /{f=0} f && /^- [A-Za-z0-9_.-]+\//{print $2}' CLAUDE.md)
    if [[ -z $repos ]]; then
      note "no allowlist entries in CLAUDE.md yet"
    else
      while IFS= read -r repo; do
        if gh repo view "$repo" --json name >/dev/null 2>&1; then
          ok "PAT can see $repo"
        else
          bad "PAT cannot see $repo (missing from the fine-grained token's repo list?)"
        fi
      done <<< "$repos"
    fi
  else
    note "CLAUDE.md not present yet — allowlist check skipped (arrives in Stage 1)"
  fi
else
  note "skipping GitHub checks (no GH_TOKEN)"
fi

echo "Notion:"
note "Notion goes via the claude.ai connector — not checkable from bash. Verified in-session (Stage 2 round-trip)."

echo
echo "check-env: $PASS passed, $FAIL failed."
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/check-env.sh
```

- [ ] **Step 3: Smoke-test the failure path (no secrets needed — this must work today)**

```bash
env -u DISCORD_BOT_TOKEN -u DISCORD_USER_ID -u DISCORD_CAPTURE_CHANNEL_ID \
    -u DISCORD_TEST_CHANNEL_ID -u GH_TOKEN bash scripts/check-env.sh; echo "exit=$?"
```

Expected: five `❌ … is missing` lines, `ℹ️ skipping Discord API checks`, `ℹ️ skipping
GitHub checks`, the Notion note, `check-env: 0 passed, 5 failed`, and `exit=1`.

- [ ] **Step 4: Commit**

```bash
git add scripts/check-env.sh
git commit -m "feat: add check-env.sh connectivity validator"
```

---

### Task 3: USER ACTION — Discord server, channels, bot

**Files:** none (web UI).

- [ ] **Step 1: Ask Stanton to complete `docs/setup.md` §1 (1.1 and 1.2)** — show him the section content inline. STOP and wait.
- [ ] **Step 2: On confirmation, collect the non-secret IDs** (`DISCORD_USER_ID`, `DISCORD_CAPTURE_CHANNEL_ID`, `DISCORD_TEST_CHANNEL_ID`) — IDs are fine in chat; the **bot token must never be pasted in chat**, it goes straight into `~/.config/second-brain/env`.

---

### Task 4: USER ACTION — GitHub fine-grained PAT + repo allowlist decision

**Files:** none (web UI).

- [ ] **Step 1: Ask Stanton for the repo allowlist** (exact `owner/repo` names the briefing should watch). This is a decision only he can make. STOP and wait.
- [ ] **Step 2: Ask him to complete `docs/setup.md` §2** with the PAT scoped to exactly those repos. Token goes straight into the env file, not chat. STOP and wait for confirmation.

---

### Task 5: USER ACTION — claude.ai connectors + work-account test

**Files:**
- Possibly modify: `docs/superpowers/specs/2026-07-06-second-brain-design.md` (dated note, only if the work connector is blocked)

- [ ] **Step 1: Ask Stanton to complete `docs/setup.md` §3** — Notion, Gmail (personal), Google Calendar (personal), the **work-account test**, and §3.3 local Notion MCP for Claude Code. STOP and wait.
- [ ] **Step 2: If the work Google account is blocked:** confirm he applied the calendar-sharing fallback, then append to the spec's "Access per service" section:

```markdown
> **2026-MM-DD:** Simply Business Google Workspace blocks claude.ai connectors. Applied
> the calendar-sharing fallback (work calendar shared into personal account,
> <event detail level>). Work-email triage moves to the roadmap (item 7).
```

- [ ] **Step 3: Verify local Notion access exists** — in this session run ToolSearch for "notion"; Notion tools must now be available (Stages 1–2 depend on them). If not, debug §3.3 with Stanton before continuing.
- [ ] **Step 4: Commit (only if the spec gained the dated note)**

```bash
git add docs/superpowers/specs/2026-07-06-second-brain-design.md
git commit -m "docs: record work Google connector outcome (dated spec note)"
```

---

### Task 6: USER ACTION — store secrets locally

- [ ] **Step 1: Ask Stanton to complete `docs/setup.md` §4** (create `~/.config/second-brain/env`, chmod 600, all five values filled). STOP and wait for confirmation.

---

### Task 7: Verify — `check-env.sh` passing locally (stage gate)

- [ ] **Step 1: Stanton runs (or asks Claude to run) the validation**

```bash
source ~/.config/second-brain/env && ./scripts/check-env.sh
```

Expected output (evidence — show Stanton the real thing):

```
Env vars:
  ✅ DISCORD_BOT_TOKEN is set
  ✅ DISCORD_USER_ID is set
  ✅ DISCORD_CAPTURE_CHANNEL_ID is set
  ✅ DISCORD_TEST_CHANNEL_ID is set
  ✅ GH_TOKEN is set
Discord:
  ✅ bot token valid (GET /users/@me → 200)
  ✅ #capture channel visible to bot (→ 200)
  ✅ #test channel visible to bot (→ 200)
  ✅ DM channel opens (POST /users/@me/channels → 200)
GitHub:
  ✅ GH_TOKEN valid (GET /user → 200)
  ℹ️  CLAUDE.md not present yet — allowlist check skipped (arrives in Stage 1)
Notion:
  ℹ️  Notion goes via the claude.ai connector — not checkable from bash. Verified in-session (Stage 2 round-trip).

check-env: 10 passed, 0 failed.
```

Exit code must be 0. Any ❌ → fix with Stanton before proceeding (systematic-debugging, not guessing).

- [ ] **Step 2: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 0 — access verified, check-env.sh passing" --allow-empty
```

(`--allow-empty` because Tasks 3–6 may produce no file changes; the commit marks the verified gate.)

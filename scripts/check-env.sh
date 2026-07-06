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

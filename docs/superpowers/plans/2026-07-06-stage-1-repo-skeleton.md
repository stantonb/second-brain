# Stage 1 — Repo Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** The repo's behavioural core: `CLAUDE.md` (the schema every run obeys), a fully tested `scripts/discord.sh`, and fixtures for skill dry-runs.

**Architecture:** `discord.sh` is a sourceable bash library + CLI (`send-dm`, `send-channel`, `fetch-captures`, `react`) with all HTTP going through one `discord_api` function that handles 429/Retry-After. Tests are bats-core with a PATH-shimmed `curl`/`sleep` stub replaying canned responses. `CLAUDE.md` holds identity, the Notion workspace map (real IDs discovered via the Notion connector), triage rules, briefing formats, and the GitHub allowlist that `check-env.sh` parses.

**Tech Stack:** bash, bats-core, jq, curl stubs, Notion connector (MCP) for ID discovery.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md`. Reality contradicts it → STOP and ask Stanton; record the agreed change in the spec with a dated note.
- Secrets only in cloud env vars + `~/.config/second-brain/env`. Never committed, never echoed.
- Never write to Notion outside "Second Brain"; never read/write `Habit Tracker`/`DND`; `CSD EL` read-only. **Stage 1 only reads Notion (search for IDs) — zero writes.**
- All date logic explicitly Europe/London.
- User-action steps: exact instructions, then STOP for Stanton's confirmation.
- Every stage ends with verification showing real output.
- Discord: 2000-char message limit; 429 + Retry-After honored; ✅ reaction only after Capture Log row (encoded in CLAUDE.md rules here).
- Commit after each task.

**Prerequisite:** Stage 0 complete (check-env.sh passing; Notion tools available in-session; repo allowlist known).

---

### Task 1: Test harness — bats-core + curl/sleep stubs

**Files:**
- Create: `tests/discord/stubs/curl`
- Create: `tests/discord/stubs/sleep`
- Create: `tests/discord/test_helper.bash`

**Interfaces:**
- Produces: `$CURL_STUB_DIR` protocol — the n-th `curl` call replays `<n>.code` (default 200), `<n>.body` (default `{}`), `<n>.headers` (default empty, copied to any `-D` target); argv appended to `calls.log`, every `-d` payload to `payloads.log`, call count in `count`; `sleep` appends its arg to `sleeps.log` and returns instantly. `setup_discord`/`teardown_discord` helpers for all bats files.

- [ ] **Step 1: Install bats-core**

```bash
brew list bats-core >/dev/null 2>&1 || brew install bats-core
bats --version
```

Expected: `Bats 1.x.x`.

- [ ] **Step 2: Write `tests/discord/stubs/curl`**

```bash
#!/usr/bin/env bash
# Test stub for curl. Replays canned responses from $CURL_STUB_DIR:
#   <n>.code (default 200), <n>.body (default {}), <n>.headers (default empty)
# for the n-th invocation. Logs argv to calls.log and -d payloads to payloads.log.
set -uo pipefail
n=$(( $(cat "$CURL_STUB_DIR/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$CURL_STUB_DIR/count"
# one line per call: escape embedded newlines (e.g. in -w formats) so line N = call N
argv="$*"
printf '%s\n' "${argv//$'\n'/\\n}" >> "$CURL_STUB_DIR/calls.log"

hdr_target=''
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
  case ${args[i]} in
    -D) hdr_target=${args[i+1]} ;;
    -d) printf '%s\n' "${args[i+1]}" >> "$CURL_STUB_DIR/payloads.log" ;;
  esac
done

code=$(cat "$CURL_STUB_DIR/$n.code" 2>/dev/null || echo 200)
body=$(cat "$CURL_STUB_DIR/$n.body" 2>/dev/null || echo '{}')
if [[ -n $hdr_target ]]; then
  if [[ -f "$CURL_STUB_DIR/$n.headers" ]]; then
    cat "$CURL_STUB_DIR/$n.headers" > "$hdr_target"
  else
    : > "$hdr_target"
  fi
fi
printf '%s\n%s' "$body" "$code"
```

- [ ] **Step 3: Write `tests/discord/stubs/sleep`**

```bash
#!/usr/bin/env bash
# Test stub for sleep: records the requested delay, sleeps not at all.
printf '%s\n' "${1:-}" >> "$CURL_STUB_DIR/sleeps.log"
```

- [ ] **Step 4: Write `tests/discord/test_helper.bash`**

```bash
# Shared setup for discord.sh bats tests.
setup_discord() {
  CURL_STUB_DIR=$(mktemp -d)
  export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export DISCORD_BOT_TOKEN='test-token'
  export DISCORD_API_BASE='https://stub.invalid/api'
  source "$BATS_TEST_DIRNAME/../../scripts/discord.sh"
}

teardown_discord() {
  rm -rf "$CURL_STUB_DIR"
}
```

- [ ] **Step 5: Make stubs executable and commit**

```bash
chmod +x tests/discord/stubs/curl tests/discord/stubs/sleep
git add tests/discord
git commit -m "test: add bats harness with curl/sleep stubs for discord.sh"
```

---

### Task 2: Test fixtures (Discord / Notion / GitHub)

**Files:**
- Create: `tests/fixtures/README.md`
- Create: `tests/fixtures/discord/captures-page-1.json`
- Create: `tests/fixtures/discord/captures-page-2.json`
- Create: `tests/fixtures/discord/captures-empty.json`
- Create: `tests/fixtures/notion/tasks.json`
- Create: `tests/fixtures/github/prs.json`

**Interfaces:**
- Produces: fixture shapes consumed by the pagination tests (Task 5) and by every skill's `FIXTURE_MODE` (Stages 3–5). Google fixtures are added in Stage 3.

- [ ] **Step 1: Write `tests/fixtures/README.md`**

```markdown
# Fixtures

Canned service data. Two consumers:

1. **bats tests** — the curl stub replays the Discord pages to test pagination.
2. **`FIXTURE_MODE=1` skill runs** — skills read these files *instead of* live services
   (no network, no Notion writes) and print the composed briefing plus a list of
   mutations they *would* have made.

Mapping used by skills in fixture mode:

| Live source | Fixture |
|---|---|
| `discord.sh fetch-captures` | `discord/captures-page-1.json` + `discord/captures-page-2.json` (concatenated, oldest first) |
| Notion Tasks DB rolling-list query | `notion/tasks.json` |
| GitHub `gh pr list` per allowlist repo | `github/prs.json` |
| Google Calendar (today) | `google/calendar-today.json` (from Stage 3) |
| Gmail triage | `google/gmail.json` (from Stage 3) |
| Notion Journal week query | `notion/journal-week.json` (from Stage 5) |
| CSD EL recently-updated sub-pages | `notion/csd-el-recent.json` (from Stage 5) |

Dates inside fixtures are fixed (early July 2026); age-dependent assertions are written
as "older than 14 days", which stays true at any later run date.
```

- [ ] **Step 2: Write `tests/fixtures/discord/captures-page-1.json`** (Discord returns newest first — the code must re-sort)

```json
[
  {
    "id": "1391402271633244161",
    "content": "done: expenses",
    "author": { "id": "111111111111111111", "username": "stanton", "bot": false },
    "timestamp": "2026-07-06T09:00:00.000000+00:00"
  },
  {
    "id": "1391402271633244160",
    "content": "https://example.com/how-to-think-in-systems",
    "author": { "id": "111111111111111111", "username": "stanton", "bot": false },
    "timestamp": "2026-07-06T08:00:00.000000+00:00"
  }
]
```

- [ ] **Step 3: Write `tests/fixtures/discord/captures-page-2.json`**

```json
[
  {
    "id": "1391402271633244162",
    "content": "waiting: Sam contract review for the DPA",
    "author": { "id": "111111111111111111", "username": "stanton", "bot": false },
    "timestamp": "2026-07-06T10:00:00.000000+00:00"
  }
]
```

- [ ] **Step 4: Write `tests/fixtures/discord/captures-empty.json`**

```json
[]
```

- [ ] **Step 5: Write `tests/fixtures/notion/tasks.json`** (simplified shape for fixture mode; covers aging, pinned-exemption, due-today rollover, waiting)

```json
[
  { "name": "Book dentist", "status": "Next", "domain": "Personal", "due": null,
    "priority": "Low", "created": "2026-06-10", "last_touched": null, "pinned": false,
    "snoozed_until": null, "rollover_count": 0, "waiting_on": null,
    "source": "manual", "source_id": "manual" },
  { "name": "Q3 roadmap draft", "status": "In progress", "domain": "Work",
    "due": "2026-07-06", "priority": "High", "created": "2026-06-28",
    "last_touched": "2026-07-03", "pinned": false, "snoozed_until": null,
    "rollover_count": 3, "waiting_on": null, "source": "manual", "source_id": "manual" },
  { "name": "Chase legal re DPA", "status": "Waiting", "domain": "Work", "due": null,
    "priority": "Medium", "created": "2026-07-01", "last_touched": "2026-07-02",
    "pinned": false, "snoozed_until": null, "rollover_count": 0, "waiting_on": "Sam",
    "source": "Discord capture", "source_id": "1391000000000000001" },
  { "name": "Renew passport", "status": "Next", "domain": "Personal",
    "due": "2026-09-01", "priority": "Medium", "created": "2026-05-20",
    "last_touched": null, "pinned": true, "snoozed_until": null, "rollover_count": 0,
    "waiting_on": null, "source": "manual", "source_id": "manual" },
  { "name": "Write blog post on routines", "status": "Next", "domain": "Personal",
    "due": null, "priority": "Low", "created": "2026-06-01",
    "last_touched": "2026-06-05", "pinned": false, "snoozed_until": null,
    "rollover_count": 0, "waiting_on": null, "source": "manual", "source_id": "manual" }
]
```

- [ ] **Step 6: Write `tests/fixtures/github/prs.json`** (repo names are canned, not the real allowlist)

```json
{
  "review_requested": [
    { "repo": "example-org/quote-engine", "number": 4123,
      "title": "Extract rating client into gem", "url": "https://github.com/example-org/quote-engine/pull/4123" }
  ],
  "mine": [
    { "repo": "example-org/quote-engine", "number": 4098,
      "title": "Rate-limit inbound webhooks", "ci": "FAILURE",
      "review": "CHANGES_REQUESTED",
      "url": "https://github.com/example-org/quote-engine/pull/4098" }
  ],
  "ci_failures": [
    { "repo": "example-org/quote-engine", "number": 4098,
      "title": "Rate-limit inbound webhooks" }
  ]
}
```

- [ ] **Step 7: Verify every fixture parses**

```bash
for f in tests/fixtures/discord/*.json tests/fixtures/notion/*.json tests/fixtures/github/*.json; do
  jq -e . "$f" > /dev/null && echo "OK $f"
done
```

Expected: `OK` for all six files.

- [ ] **Step 8: Commit**

```bash
git add tests/fixtures
git commit -m "test: add Discord/Notion/GitHub fixtures for tests and FIXTURE_MODE"
```

---

### Task 3: `split_message` (TDD)

**Files:**
- Create: `tests/discord/split_message.bats`
- Create: `scripts/discord.sh` (skeleton + `split_message`)

**Interfaces:**
- Produces: `split_message OUTDIR` — reads stdin, writes chunks ≤ 2000 chars to `OUTDIR/chunk-001…N`, newline-boundary splits, hard-split for oversized single lines. Constant `MAX_LEN=2000`. Consumed by `send_channel` (Task 6).

- [ ] **Step 1: Write the failing tests — `tests/discord/split_message.bats`**

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; OUTDIR=$(mktemp -d); }
teardown() { teardown_discord; rm -rf "$OUTDIR"; }

@test "short text becomes a single chunk" {
  printf 'hello world' | split_message "$OUTDIR"
  [ "$(ls "$OUTDIR" | wc -l | tr -d ' ')" = "1" ]
  [ "$(cat "$OUTDIR/chunk-001")" = "hello world" ]
}

@test "multi-line text under 2000 chars stays one chunk" {
  printf 'line one\nline two\nline three' | split_message "$OUTDIR"
  [ "$(ls "$OUTDIR" | wc -l | tr -d ' ')" = "1" ]
}

@test "3000 chars of 99-char lines splits into 2 chunks at line boundaries" {
  line=$(head -c 99 </dev/zero | tr '\0' '=')
  { for _ in $(seq 30); do echo "$line"; done; } | split_message "$OUTDIR"
  [ "$(ls "$OUTDIR" | wc -l | tr -d ' ')" = "2" ]
  [ "$(wc -c < "$OUTDIR/chunk-001" | tr -d ' ')" -le 2000 ]
  # no line was cut in half: every line in chunk 1 is exactly 99 '='
  run grep -Ecv '^={99}$' "$OUTDIR/chunk-001"
  [ "$output" = "0" ]
}

@test "a single 4500-char line hard-splits into 3 chunks" {
  head -c 4500 </dev/zero | tr '\0' 'x' | split_message "$OUTDIR"
  [ "$(ls "$OUTDIR" | wc -l | tr -d ' ')" = "3" ]
  [ "$(wc -c < "$OUTDIR/chunk-001" | tr -d ' ')" = "2000" ]
  [ "$(wc -c < "$OUTDIR/chunk-003" | tr -d ' ')" = "500" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/discord/split_message.bats`
Expected: FAIL — `scripts/discord.sh: No such file or directory` (the `source` in `setup_discord` fails).

- [ ] **Step 3: Write `scripts/discord.sh`** (header, constants, `split_message`, main guard — later tasks add functions to this same file)

```bash
#!/usr/bin/env bash
# discord.sh — all Discord I/O for the second brain goes through here.
#
# Commands (message text is read from stdin where applicable):
#   send-dm                                DM $DISCORD_USER_ID (splits at 2000 chars)
#   send-channel <channel_id>              post to a channel (same splitting)
#   fetch-captures <channel_id> [after_id] full paginated history after <after_id>
#                                          (default: from the start) as a JSON array,
#                                          oldest first
#   react <channel_id> <message_id> [emoji]  add a reaction (default ✅)
#
# Env: DISCORD_BOT_TOKEN (always), DISCORD_USER_ID (send-dm),
#      DISCORD_API_BASE (test seam; default https://discord.com/api/v10).

API_BASE="${DISCORD_API_BASE:-https://discord.com/api/v10}"
MAX_LEN=2000
MAX_RETRIES=5

# split_message OUTDIR — stdin → OUTDIR/chunk-001..N, each ≤ MAX_LEN chars.
# Splits at newline boundaries; single lines > MAX_LEN are hard-split.
split_message() {
  local outdir=$1 n=0 chunk='' line candidate
  _flush() {
    if [[ -n $chunk ]]; then
      n=$((n + 1))
      printf '%s' "$chunk" > "$outdir/$(printf 'chunk-%03d' "$n")"
      chunk=''
    fi
  }
  while IFS= read -r line || [[ -n $line ]]; do
    while (( ${#line} > MAX_LEN )); do
      _flush
      chunk=${line:0:MAX_LEN}
      _flush
      line=${line:MAX_LEN}
    done
    if [[ -z $chunk ]]; then
      candidate=$line
    else
      candidate=$chunk$'\n'$line
    fi
    if (( ${#candidate} > MAX_LEN )); then
      _flush
      chunk=$line
    else
      chunk=$candidate
    fi
  done
  _flush
  unset -f _flush
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  : "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN must be set}"
  main "$@"
fi
```

- [ ] **Step 4: Run to verify pass**

Run: `chmod +x scripts/discord.sh && bats tests/discord/split_message.bats`
Expected: `4 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/discord.sh tests/discord/split_message.bats
git commit -m "feat: discord.sh split_message with 2000-char newline-aware splitting (TDD)"
```

---

### Task 4: `discord_api` with 429/Retry-After handling (TDD)

**Files:**
- Create: `tests/discord/discord_api.bats`
- Modify: `scripts/discord.sh` (add `discord_api` above `split_message`)

**Interfaces:**
- Produces: `discord_api METHOD PATH [JSON_BODY]` → prints response body, returns 0 on 2xx; retries 429 up to `MAX_RETRIES` honoring `Retry-After` header, then JSON `retry_after`, then exponential backoff; returns 1 on other errors with a stderr line. A third argument of `''` sends an empty body (Content-Length: 0). Consumed by every other function.

- [ ] **Step 1: Write the failing tests — `tests/discord/discord_api.bats`**

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; }
teardown() { teardown_discord; }

@test "2xx returns the body" {
  echo 200 > "$CURL_STUB_DIR/1.code"
  printf '{"id":"42"}' > "$CURL_STUB_DIR/1.body"
  run discord_api GET /users/@me
  [ "$status" -eq 0 ]
  [ "$output" = '{"id":"42"}' ]
}

@test "429 sleeps for Retry-After then retries" {
  echo 429 > "$CURL_STUB_DIR/1.code"
  printf 'Retry-After: 3\r\n' > "$CURL_STUB_DIR/1.headers"
  printf '{"retry_after":3.0}' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"
  printf '{"ok":true}' > "$CURL_STUB_DIR/2.body"
  run discord_api GET /channels/1/messages
  [ "$status" -eq 0 ]
  [ "$output" = '{"ok":true}' ]
  [ "$(cat "$CURL_STUB_DIR/sleeps.log")" = "3" ]
}

@test "gives up after MAX_RETRIES consecutive 429s" {
  for i in 1 2 3 4 5 6; do
    echo 429 > "$CURL_STUB_DIR/$i.code"
    printf 'Retry-After: 0\r\n' > "$CURL_STUB_DIR/$i.headers"
  done
  run discord_api GET /users/@me
  [ "$status" -eq 1 ]
  [ "$(cat "$CURL_STUB_DIR/count")" = "6" ]
}

@test "non-2xx non-429 fails and reports the code" {
  echo 403 > "$CURL_STUB_DIR/1.code"
  printf '{"message":"Missing Access"}' > "$CURL_STUB_DIR/1.body"
  run discord_api GET /channels/999
  [ "$status" -eq 1 ]
  [[ "$output" == *"403"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/discord/discord_api.bats`
Expected: 4 failures — `discord_api: command not found`.

- [ ] **Step 3: Add `discord_api` to `scripts/discord.sh`** (insert between the constants and `split_message`)

```bash
# discord_api METHOD PATH [JSON_BODY] — prints the response body on success.
# Honors 429 Retry-After (header → JSON body → exponential backoff), MAX_RETRIES cap.
discord_api() {
  local method=$1 path=$2 attempt=0
  local hdrs resp code body retry_after
  hdrs=$(mktemp)
  while :; do
    if (( $# >= 3 )); then
      resp=$(curl -sS -X "$method" -D "$hdrs" -w $'\n%{http_code}' \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        -H 'Content-Type: application/json' \
        -d "$3" "$API_BASE$path")
    else
      resp=$(curl -sS -X "$method" -D "$hdrs" -w $'\n%{http_code}' \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        "$API_BASE$path")
    fi
    code=${resp##*$'\n'}
    body=${resp%$'\n'*}
    if [[ $code == 429 ]]; then
      attempt=$((attempt + 1))
      if (( attempt > MAX_RETRIES )); then
        rm -f "$hdrs"
        echo "discord_api: still rate-limited after $MAX_RETRIES retries: $method $path" >&2
        return 1
      fi
      retry_after=$(awk 'tolower($1)=="retry-after:" {gsub("\r",""); print $2}' "$hdrs")
      if [[ -z $retry_after ]]; then
        retry_after=$(jq -r '.retry_after // empty' <<<"$body" 2>/dev/null || true)
      fi
      if [[ -z $retry_after ]]; then
        retry_after=$(( 2 ** attempt ))
      fi
      sleep "$retry_after"
      continue
    fi
    rm -f "$hdrs"
    if [[ $code == 2* ]]; then
      printf '%s' "$body"
      return 0
    fi
    echo "discord_api: $method $path → HTTP $code: $body" >&2
    return 1
  done
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/discord/discord_api.bats`
Expected: `4 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/discord.sh tests/discord/discord_api.bats
git commit -m "feat: discord_api wrapper with 429/Retry-After + backoff (TDD)"
```

---

### Task 5: `fetch_captures` pagination (TDD)

**Files:**
- Create: `tests/discord/fetch_captures.bats`
- Modify: `scripts/discord.sh` (add `fetch_captures` after `discord_api`)

**Interfaces:**
- Consumes: `discord_api` (Task 4), Discord fixture pages (Task 2).
- Produces: `fetch_captures CHANNEL_ID [AFTER_ID]` → prints one JSON array of all messages after AFTER_ID (default `0`), **oldest first**, paging `limit=100` with the `after` cursor until an empty page. Consumed by the skills' capture triage.

- [ ] **Step 1: Write the failing tests — `tests/discord/fetch_captures.bats`**

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; FIX="$BATS_TEST_DIRNAME/../fixtures/discord"; }
teardown() { teardown_discord; }

@test "pages with the after cursor until an empty page, oldest first" {
  cp "$FIX/captures-page-1.json" "$CURL_STUB_DIR/1.body"; echo 200 > "$CURL_STUB_DIR/1.code"
  cp "$FIX/captures-page-2.json" "$CURL_STUB_DIR/2.body"; echo 200 > "$CURL_STUB_DIR/2.code"
  cp "$FIX/captures-empty.json"  "$CURL_STUB_DIR/3.body"; echo 200 > "$CURL_STUB_DIR/3.code"
  run fetch_captures 555 0
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" = "3" ]
  [ "$(jq -r '.[0].id' <<<"$output")" = "1391402271633244160" ]
  [ "$(jq -r '.[2].id' <<<"$output")" = "1391402271633244162" ]
  # cursor advanced to the newest id of each page
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=0')" = "1" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=1391402271633244161')" = "1" ]
  [ "$(sed -n '3p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=1391402271633244162')" = "1" ]
}

@test "empty channel yields an empty JSON array" {
  cp "$FIX/captures-empty.json" "$CURL_STUB_DIR/1.body"; echo 200 > "$CURL_STUB_DIR/1.code"
  run fetch_captures 555
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" = "0" ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/discord/fetch_captures.bats`
Expected: 2 failures — `fetch_captures: command not found`.

- [ ] **Step 3: Add `fetch_captures` to `scripts/discord.sh`**

```bash
# fetch_captures CHANNEL_ID [AFTER_ID] — prints a JSON array, oldest first.
# Pages with limit=100 + the `after` cursor until an empty page: full catch-up,
# never a recency window.
fetch_captures() {
  local channel_id=$1 after=${2:-0} page combined='[]'
  while :; do
    page=$(discord_api GET "/channels/$channel_id/messages?limit=100&after=$after") || return 1
    # Snowflake ids overflow jq numbers — sort by (length, string) ≡ numeric order.
    page=$(jq 'sort_by([(.id | length), .id])' <<<"$page")
    if [[ $(jq 'length' <<<"$page") -eq 0 ]]; then
      break
    fi
    combined=$(jq -s '.[0] + .[1]' <<<"$combined$page")
    after=$(jq -r '.[-1].id' <<<"$page")
  done
  printf '%s\n' "$combined"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/discord/fetch_captures.bats`
Expected: `2 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/discord.sh tests/discord/fetch_captures.bats
git commit -m "feat: fetch_captures full-history pagination via after cursor (TDD)"
```

---

### Task 6: `send_channel`, `send_dm`, `react`, CLI dispatch (TDD)

**Files:**
- Create: `tests/discord/send_react.bats`
- Modify: `scripts/discord.sh` (add remaining functions + `usage` + `main`)

**Interfaces:**
- Consumes: `discord_api`, `split_message`.
- Produces: `send_channel CHANNEL_ID` (stdin → one POST per chunk), `send_dm` (stdin → opens DM channel with `$DISCORD_USER_ID`, then `send_channel`), `react CHANNEL_ID MESSAGE_ID [EMOJI=✅]` (URL-encoded PUT, empty body), and the CLI: `discord.sh {send-dm|send-channel|fetch-captures|react}`. Consumed by all skills.

- [ ] **Step 1: Write the failing tests — `tests/discord/send_react.bats`**

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; }
teardown() { teardown_discord; }

@test "send_channel splits long input into one POST per chunk" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{}' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '{}' > "$CURL_STUB_DIR/2.body"
  line=$(head -c 1500 </dev/zero | tr '\0' 'a')
  printf '%s\n%s' "$line" "$line" | send_channel 555
  [ "$(cat "$CURL_STUB_DIR/count")" = "2" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.content | length')" = "1500" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/555/messages')" = "1" ]
}

@test "send_dm opens the DM channel then posts to it" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"999000"}' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '{}' > "$CURL_STUB_DIR/2.body"
  export DISCORD_USER_ID='111111111111111111'
  printf 'good morning' | send_dm
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/users/@me/channels')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.recipient_id')" = "111111111111111111" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/999000/messages')" = "1" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/payloads.log" | jq -r '.content')" = "good morning" ]
}

@test "react PUTs the URL-encoded ✅" {
  echo 204 > "$CURL_STUB_DIR/1.code"; : > "$CURL_STUB_DIR/1.body"
  run react 555 1001
  [ "$status" -eq 0 ]
  [ "$(grep -c '%E2%9C%85' "$CURL_STUB_DIR/calls.log")" = "1" ]
}

@test "CLI: unknown command prints usage and exits 2" {
  DISCORD_BOT_TOKEN=t run bash scripts/discord.sh bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/discord/send_react.bats`
Expected: failures — `send_channel: command not found` etc.

- [ ] **Step 3: Add the remaining functions to `scripts/discord.sh`** (after `fetch_captures`, before the `BASH_SOURCE` guard)

```bash
# send_channel CHANNEL_ID — stdin → one or more POSTs (2000-char chunks).
send_channel() {
  local channel_id=$1 dir f payload
  dir=$(mktemp -d)
  split_message "$dir"
  for f in "$dir"/chunk-*; do
    [[ -e $f ]] || { echo 'send_channel: empty message — nothing sent' >&2; break; }
    payload=$(jq -Rs '{content: .}' "$f")
    discord_api POST "/channels/$channel_id/messages" "$payload" > /dev/null || { rm -rf "$dir"; return 1; }
  done
  rm -rf "$dir"
}

# send_dm — stdin → DM to $DISCORD_USER_ID (opens/reuses the DM channel).
send_dm() {
  local dm_channel
  dm_channel=$(discord_api POST '/users/@me/channels' \
    "{\"recipient_id\":\"$DISCORD_USER_ID\"}" | jq -r '.id')
  send_channel "$dm_channel"
}

# react CHANNEL_ID MESSAGE_ID [EMOJI] — default ✅. Empty body → Content-Length: 0.
react() {
  local channel_id=$1 message_id=$2 emoji=${3:-✅} encoded
  encoded=$(jq -rn --arg e "$emoji" '$e | @uri')
  discord_api PUT "/channels/$channel_id/messages/$message_id/reactions/$encoded/@me" '' > /dev/null
}

usage() {
  cat >&2 <<'EOF'
usage: discord.sh <command>
  send-dm                                  DM $DISCORD_USER_ID (text on stdin)
  send-channel <channel_id>                post to channel (text on stdin)
  fetch-captures <channel_id> [after_id]   full history as JSON, oldest first
  react <channel_id> <message_id> [emoji]  add reaction (default ✅)
EOF
  exit 2
}

main() {
  local cmd=${1:-}
  shift || true
  case $cmd in
    send-dm)        : "${DISCORD_USER_ID:?DISCORD_USER_ID must be set}"; send_dm ;;
    send-channel)   send_channel "${1:?usage: discord.sh send-channel <channel_id>}" ;;
    fetch-captures) fetch_captures "${1:?usage: discord.sh fetch-captures <channel_id> [after_id]}" "${2:-0}" ;;
    react)          react "${1:?channel_id required}" "${2:?message_id required}" "${3:-✅}" ;;
    *)              usage ;;
  esac
}
```

- [ ] **Step 4: Run the full suite**

Run: `bats tests/discord/`
Expected: `14 tests, 0 failures` (4 split + 4 api + 2 fetch + 4 send/react).

- [ ] **Step 5: Commit**

```bash
git add scripts/discord.sh tests/discord/send_react.bats
git commit -m "feat: discord.sh send/react commands + CLI dispatch (TDD)"
```

---

### Task 7: Discover real Notion IDs (read-only) — USER CONFIRMATION GATE

**Files:** none yet (IDs land in `CLAUDE.md` in Task 8).

**Interfaces:**
- Consumes: Notion connector tools (available since Stage 0 Task 5).
- Produces: confirmed page/database IDs + types for `CSD EL`, `Habit Tracker`, `DND`.

- [ ] **Step 1: Load Notion tools** — `ToolSearch "select:..."` after finding them via query "notion". Use the connector's search tool.
- [ ] **Step 2: Search, read-only, for each structure**: search `CSD EL`, `Habit Tracker`, `DND`. For each record: exact title, object type (page/database), ID, parent. **Do not open/read the content of Habit Tracker or DND — the search hit (title, id) is all that is needed; they are excluded structures.**
- [ ] **Step 3: Show Stanton the three (title, type, id) rows and ask him to confirm each is the right structure.** Misidentified exclusion IDs would be dangerous. STOP and wait.

---

### Task 8: `CLAUDE.md` schema file

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: confirmed IDs (Task 7), repo allowlist (Stage 0 Task 4).
- Produces: the schema every skill reads. The `## GitHub repo allowlist` heading and `- owner/repo` bullet format are load-bearing (parsed by `check-env.sh`). Section names `## Briefing formats`, `## Triage intent rules`, `## Notion workspace map` are referenced by the Stage 3–5 skills.

- [ ] **Step 1: Write `CLAUDE.md` with this content** — replace `<csd-el-id>`, `<habit-tracker-id>`, `<dnd-id>`, `<type>` with Task 7's confirmed values and the allowlist bullets with Stanton's real repos (from Stage 0). The `*(Stage 2)*` ID cells are filled by the Stage 2 plan.

````markdown
# Second Brain — schema

This repo is the behaviour of Stanton Borthwick's second brain. State lives in Notion,
delivery is Discord DM, and this file is the contract every run follows. Read it in full
before acting.

## Identity & tone

- You are Stanton's second brain: a blunt, warm chief-of-staff.
- Audience: Stanton only, via Discord. British English. Concise — every line earns its place.
- Honest over comfortable: report rollovers, gaps, and failures plainly. Never pad.

## Timezone rule

All "today"/"tomorrow" logic, date queries, run IDs, and Journal titles resolve in
**Europe/London**, explicitly — cloud runs default to UTC. In shell:
`TZ=Europe/London date +%F`. Never rely on system-default time.

## Run conventions

- **Run ID:** `{type}-{YYYY-MM-DD}` (Europe/London date), e.g. `morning-2026-07-06`.
  Dry runs append `-test`.
- **Idempotency:** before writing, look up the Journal page titled with the run ID —
  update it (noting "rerun") rather than duplicating. A manual rerun must never
  double-create tasks or Journal entries.
- **Capture dedupe:** the Capture Log (Message ID) is the source of truth for what has
  been processed. Write the Capture Log row first; add the ✅ reaction only after —
  a crash between the two re-processes nothing.
- **Rule #1 — never fail silent:** if a service is unreachable, still deliver the DM with
  whatever succeeded plus an explicit "⚠️ couldn't reach <service>" line. If Discord
  itself is down, write the Journal anyway (the DM is delivery; Notion is truth).

## Notion workspace map

| Structure | Type | ID | Access |
|---|---|---|---|
| Second Brain | page | *(Stage 2)* | read/write — the ONLY place the brain writes |
| Tasks | database | *(Stage 2)* | read/write |
| Journal | database | *(Stage 2)* | read/write |
| Capture Log | database | *(Stage 2)* | read/write |
| Reading list | database | *(Stage 2)* | read/write |
| Brag doc | page | *(Stage 2)* | append via weekly review only |
| CSD EL | page | `<csd-el-id>` | **READ-ONLY** — never write, rename, restructure, or append |
| Habit Tracker | `<type>` | `<habit-tracker-id>` | **EXCLUDED — never read, never write** |
| DND | `<type>` | `<dnd-id>` | **EXCLUDED — never read, never write** |

Everything else in the workspace: readable as context; **no writes outside Second Brain**.

## Task schema

Properties on the Tasks database (created in Stage 2):

| Property | Type | Meaning |
|---|---|---|
| Name | title | |
| Status | select | `Inbox / Next / In progress / Waiting / Done / Dropped` |
| Domain | select | `Work / Personal` |
| Project/Area | select | grows organically |
| Due | date | |
| Priority | select | `High / Medium / Low` |
| Created | created time | automatic |
| Completed | date | set when Status → Done |
| Waiting-on | text | person, used with Status `Waiting` |
| Blocked Reason | text | used with `Waiting` |
| Snoozed Until | date | hidden from briefings until then |
| Pinned | checkbox | exempt from aging flags and cull proposals |
| Rollover Count | number | incremented by the evening run |
| Last Rolled Over | date | set by the evening run |
| Last Touched | date | any brain- or capture-driven update |
| Source | text | human-readable origin |
| Source ID | text | dedupe key: Discord message ID, Gmail message ID, GitHub PR URL, or `manual` |

**Rolling list** = Status ∈ {`Next`, `In progress`, `Waiting`}, excluding tasks whose
Snoozed Until is after today. Rollover state lives in these properties, updated by the
evening run — never parsed back out of Journal prose.

### Aging rules

- Age = days since Last Touched (fall back to Created).
- In `Next`/`In progress` **> 14 days** → flagged in briefings with age (⏳).
- **> 30 days** → weekly review proposes `Dropped`; Stanton confirms via a `drop:` capture.
- **Pinned** tasks are exempt from both; **snoozed** tasks don't age until they wake.

## Triage intent rules

Apply to each unprocessed `#capture` message, first match wins:

1. `note: <text>` → note appended to today's Journal page (skips task inference).
2. `done: <text>` / `drop: <text>` → fuzzy-match one open Task; set Status
   `Done`/`Dropped` **only if the match is unambiguous** (one clear candidate). For
   `done:` also set Completed + Last Touched. Ambiguous or no match → Capture Log row
   with Outcome `Needs Review`, surfaced in the next DM's decisions-needed section —
   **never guess**.
3. `snooze: <task> until <date>` → set Snoozed Until (date parsed in Europe/London).
4. `waiting: <person> <thing>` → Task with Status `Waiting`, Waiting-on = person.
5. `meeting: <text>` → reserved for Phase 2; until then treat as a Journal note and say
   so in the next briefing.
6. Bare URL (optional trailing comment) → Reading list row (Name = comment or page
   title, Status `Unread`).
7. Anything actionable → Task: infer Domain, Due, Priority; Status `Inbox`, promoted to
   `Next` if clearly actionable now. Source = `Discord capture`, Source ID = message ID.
8. Anything else → note appended to today's Journal page.

Every processed capture gets a Capture Log row (Message ID, Raw Text, Processed At,
Outcome, Confidence, Link) **then** a ✅ reaction, and is counted in the next briefing
("Captured: 3 tasks, 1 link").

## Briefing formats

Omit a section entirely when it has no content. `⚠️ couldn't reach <service>` lines go
at the bottom. Discord markdown; keep each briefing scannable on a phone.

### Morning

```text
**🌅 Morning briefing — {Ddd D Mon YYYY}**

**📥 Captured since last run:** {counts by outcome, or "nothing new"}

**📅 Today**
- {HH:MM}–{HH:MM}  {event}   (all connected calendars)
- Gaps: {gaps ≥ 45 min between 09:00–18:00}

**🎯 Top 3**
1. {task} — {why: due/priority/age}
2. …
3. …

**📋 Rolling list**   (⏳ aging · 🔒 pinned · [W] waiting)
- {task} ({status}{, due …})
- [W] {task} — waiting on {person}
- ⏳ {task} — {age} days

**📧 Email**
- Reply needed: {sender} — {subject}
- Deadline spotted: {what, when}
- Waiting on: {person} — {subject} (sent {N}d ago, no reply)

**🔀 GitHub**
- Needs your review: {repo}#{n} {title}
- Yours: {repo}#{n} — {CI/review state}
- CI failed overnight: {repo}#{n}

**❓ Decisions needed**
- "{raw capture}" — reply `done: …` / `drop: …` / tell me what it is
```

### Evening

```text
**🌙 Evening shutdown — {Ddd D Mon YYYY}**

**📥 Captured today:** {counts, or "nothing new"}

**✅ Done today**
- {task}

**🔁 Rolled over**   (counts from Task properties, honestly)
- {task} — {ordinal} time

**❓ Decisions needed** (carried forward)
- …

**🌄 Tomorrow**
- First meeting: {HH:MM} {event}
- Shape: {one line}
```

### Weekly

```text
**🗓 Weekly review — w/e {Ddd D Mon YYYY}**

**🏆 Wins**
- …

**🕳 Dropped balls**
- …

**🧹 Stale (>30 days — propose Dropped)**   reply `drop: {name}` to confirm; snooze or pin to keep
- {task} — {age} days

**📈 Next week**
- {shape, first meetings, due items}

**📓 Brag doc:** appended {N} items

**🩺 Self-check:** {N}/14 journal entries{ — missing: {run IDs}}
```

## GitHub repo allowlist

The briefing reads PRs/CI **only** from these repos; the fine-grained PAT is scoped to
match. `scripts/check-env.sh` parses the bullets — keep the exact `- owner/repo` format.

- <owner/repo-from-stage-0>

## Discord

- All Discord I/O goes through `scripts/discord.sh` (429/Retry-After, 2000-char splits).
- Briefings: DM Stanton (`DISCORD_USER_ID`). Dry runs post to `#test`
  (`DISCORD_TEST_CHANNEL_ID`) instead.
- Captures: page through `#capture` (`DISCORD_CAPTURE_CHANNEL_ID`) with the `after`
  cursor from the highest processed Message ID — full catch-up, never a recency window.
  Ignore messages authored by the bot itself.

## Secrets

`DISCORD_BOT_TOKEN`, `DISCORD_USER_ID`, `DISCORD_CAPTURE_CHANNEL_ID`,
`DISCORD_TEST_CHANNEL_ID`, `GH_TOKEN` — environment variables only. Never commit,
print, or log them.
````

- [ ] **Step 2: Verify `check-env.sh` now validates the allowlist**

Run: `source ~/.config/second-brain/env && ./scripts/check-env.sh`
Expected: previous ✅ lines plus one `✅ PAT can see <owner/repo>` per allowlist entry; exit 0.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: CLAUDE.md schema — workspace map, triage rules, formats, allowlist"
```

---

### Task 9: Stage verification

- [ ] **Step 1: Full evidence run** — show Stanton the real output of:

```bash
bats tests/discord/ && (source ~/.config/second-brain/env && ./scripts/check-env.sh)
```

Expected: `14 tests, 0 failures` and `check-env: N passed, 0 failed`.

- [ ] **Step 2: Show Stanton the rendered Notion workspace map table from `CLAUDE.md`** (the three discovered IDs with access rules) for a final read-through.

- [ ] **Step 3: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 1 — repo skeleton (CLAUDE.md, discord.sh, fixtures)" --allow-empty
```

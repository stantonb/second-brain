# Stage 2 Addendum — `scripts/notion.sh` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deterministic Notion reads (and page archival) on any Notion plan, via a free internal-integration token + the public REST API — because the connector's query tools are plan-gated (spec note 2026-07-07).

**Architecture:** `scripts/notion.sh` mirrors `scripts/discord.sh`: one `notion_api` curl wrapper (Bearer token, `Notion-Version: 2025-09-03`, 429/Retry-After with backoff), `query` with full `has_more`/`next_cursor` pagination against `POST /v1/data_sources/{id}/query`, `archive`, `whoami`. Skills read via this; the connector keeps creation/content/search.

**Tech Stack:** bash, curl, jq, bats (reusing `tests/discord/stubs`).

## Global Constraints

Same as all stage plans (spec is source of truth; secrets only in env vars; Second Brain-only writes; CSD EL read-only behavioural; Europe/London; user-action steps stop for confirmation; evidence before claims; commit per task).

---

### Task 1: TDD `notion.sh`

**Files:**
- Create: `tests/notion/test_helper.bash`
- Create: `tests/notion/notion.bats`
- Create: `tests/fixtures/notion/query-page-1.json`, `tests/fixtures/notion/query-page-2.json`
- Create: `scripts/notion.sh`

**Interfaces:**
- Produces: `notion_api METHOD PATH [JSON]`; `query_db DATA_SOURCE_ID [FILTER_JSON]` → JSON array of all results (paginated); `archive_page PAGE_ID`; CLI `notion.sh {query|archive|whoami}`. Consumed by Stages 3–5 skills for every structured read.

- [ ] **Step 1: fixtures** — `query-page-1.json`:

```json
{ "object": "list", "results": [ { "id": "t1" }, { "id": "t2" } ],
  "has_more": true, "next_cursor": "cursor-abc" }
```

`query-page-2.json`:

```json
{ "object": "list", "results": [ { "id": "t3" } ],
  "has_more": false, "next_cursor": null }
```

- [ ] **Step 2: `tests/notion/test_helper.bash`**

```bash
# Shared setup for notion.sh bats tests. Reuses the discord curl/sleep stubs.
setup_notion() {
  CURL_STUB_DIR=$(mktemp -d)
  export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/../discord/stubs:$PATH"
  export NOTION_TOKEN='test-token'
  export NOTION_API_BASE='https://stub.invalid/v1'
  source "$BATS_TEST_DIRNAME/../../scripts/notion.sh"
}

teardown_notion() {
  rm -rf "$CURL_STUB_DIR"
}
```

- [ ] **Step 3: failing tests — `tests/notion/notion.bats`**

```bash
#!/usr/bin/env bats
load test_helper

setup()    { setup_notion; FIX="$BATS_TEST_DIRNAME/../fixtures/notion"; }
teardown() { teardown_notion; }

@test "notion_api sends Bearer auth and Notion-Version headers" {
  echo 200 > "$CURL_STUB_DIR/1.code"
  printf '{"object":"user"}' > "$CURL_STUB_DIR/1.body"
  run notion_api GET /users/me
  [ "$status" -eq 0 ]
  [ "$output" = '{"object":"user"}' ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c 'Bearer test-token')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c 'Notion-Version:')" = "1" ]
}

@test "429 honors Retry-After then retries" {
  echo 429 > "$CURL_STUB_DIR/1.code"
  printf 'Retry-After: 2\r\n' > "$CURL_STUB_DIR/1.headers"
  echo 200 > "$CURL_STUB_DIR/2.code"
  printf '{"ok":true}' > "$CURL_STUB_DIR/2.body"
  run notion_api GET /users/me
  [ "$status" -eq 0 ]
  [ "$(cat "$CURL_STUB_DIR/sleeps.log")" = "2" ]
}

@test "query paginates with next_cursor until has_more is false" {
  cp "$FIX/query-page-1.json" "$CURL_STUB_DIR/1.body"; echo 200 > "$CURL_STUB_DIR/1.code"
  cp "$FIX/query-page-2.json" "$CURL_STUB_DIR/2.body"; echo 200 > "$CURL_STUB_DIR/2.code"
  run query_db ds-123 '{"property":"Status","select":{"equals":"Next"}}'
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" = "3" ]
  [ "$(jq -r '.[2].id' <<<"$output")" = "t3" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.filter.property')" = "Status" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.start_cursor // "none"')" = "none" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/payloads.log" | jq -r '.start_cursor')" = "cursor-abc" ]
}

@test "archive PATCHes archived:true" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{}' > "$CURL_STUB_DIR/1.body"
  run archive_page page-9
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.archived')" = "true" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/pages/page-9')" = "1" ]
}

@test "CLI: unknown command prints usage and exits 2" {
  run bash scripts/notion.sh bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
```

- [ ] **Step 4: run to verify failure** — `bats tests/notion/` → `No such file` (notion.sh missing).

- [ ] **Step 5: implement `scripts/notion.sh`**

```bash
#!/usr/bin/env bash
# notion.sh — structured Notion reads (and archival) via the public REST API.
# Exists because the connector's query tools are plan-gated (spec note 2026-07-07);
# the claude.ai connector remains the path for page creation/content/search.
#
# Commands:
#   query <data_source_id> [filter_json]   POST /v1/data_sources/{id}/query with full
#                                          pagination; prints a JSON array of results
#   archive <page_id>                      move a page to trash
#   whoami                                 GET /v1/users/me (auth check)
#
# Env: NOTION_TOKEN (required), NOTION_API_BASE (test seam),
#      NOTION_VERSION (default 2025-09-03).

API_BASE="${NOTION_API_BASE:-https://api.notion.com/v1}"
NOTION_VERSION="${NOTION_VERSION:-2025-09-03}"
MAX_RETRIES=5

# notion_api METHOD PATH [JSON_BODY] — prints the response body on success.
# Honors 429 Retry-After (header → exponential backoff), MAX_RETRIES cap.
notion_api() {
  local method=$1 path=$2 attempt=0
  local hdrs resp code body retry_after
  hdrs=$(mktemp)
  while :; do
    if (( $# >= 3 )); then
      resp=$(curl -sS -X "$method" -D "$hdrs" -w $'\n%{http_code}' \
        -H "Authorization: Bearer $NOTION_TOKEN" \
        -H "Notion-Version: $NOTION_VERSION" \
        -H 'Content-Type: application/json' \
        -d "$3" "$API_BASE$path")
    else
      resp=$(curl -sS -X "$method" -D "$hdrs" -w $'\n%{http_code}' \
        -H "Authorization: Bearer $NOTION_TOKEN" \
        -H "Notion-Version: $NOTION_VERSION" \
        "$API_BASE$path")
    fi
    code=${resp##*$'\n'}
    body=${resp%$'\n'*}
    if [[ $code == 429 ]]; then
      attempt=$((attempt + 1))
      if (( attempt > MAX_RETRIES )); then
        rm -f "$hdrs"
        echo "notion_api: still rate-limited after $MAX_RETRIES retries: $method $path" >&2
        return 1
      fi
      retry_after=$(awk 'tolower($1)=="retry-after:" {gsub("\r",""); print $2}' "$hdrs")
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
    echo "notion_api: $method $path → HTTP $code: $body" >&2
    return 1
  done
}

# query_db DATA_SOURCE_ID [FILTER_JSON] — prints a JSON array of every matching
# page object, following has_more/next_cursor to the end (never a partial read).
query_db() {
  local ds_id=$1 filter=${2:-} cursor='' combined='[]' body page has_more
  while :; do
    body='{"page_size": 100}'
    if [[ -n $filter ]]; then
      body=$(jq -c --argjson f "$filter" '. + {filter: $f}' <<<"$body")
    fi
    if [[ -n $cursor ]]; then
      body=$(jq -c --arg c "$cursor" '. + {start_cursor: $c}' <<<"$body")
    fi
    page=$(notion_api POST "/data_sources/$ds_id/query" "$body") || return 1
    combined=$(jq -s '.[0] + .[1].results' <<<"$combined$page")
    has_more=$(jq -r '.has_more' <<<"$page")
    if [[ $has_more != true ]]; then
      break
    fi
    cursor=$(jq -r '.next_cursor' <<<"$page")
  done
  printf '%s\n' "$combined"
}

# archive_page PAGE_ID — move to trash (the connector cannot).
archive_page() {
  notion_api PATCH "/pages/$1" '{"archived": true}' > /dev/null
}

usage() {
  cat >&2 <<'EOF'
usage: notion.sh <command>
  query <data_source_id> [filter_json]   all matching rows as a JSON array
  archive <page_id>                      move a page to trash
  whoami                                 auth check (GET /users/me)
EOF
  exit 2
}

main() {
  local cmd=${1:-}
  shift || true
  case $cmd in
    query)   query_db "${1:?usage: notion.sh query <data_source_id> [filter_json]}" "${2:-}" ;;
    archive) archive_page "${1:?page_id required}" ;;
    whoami)  notion_api GET /users/me ;;
    *)       usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  : "${NOTION_TOKEN:?NOTION_TOKEN must be set}"
  main "$@"
fi
```

- [ ] **Step 6: run to verify pass** — `chmod +x scripts/notion.sh && bats tests/notion/` → `5 tests, 0 failures`.
- [ ] **Step 7: commit** — `git add scripts/notion.sh tests/notion tests/fixtures/notion && git commit -m "feat: notion.sh REST reads + archival (TDD)"`.

---

### Task 2: Wire into check-env, setup runbook, CLAUDE.md

**Files:**
- Modify: `scripts/check-env.sh` (NOTION_TOKEN in the env-var loop; Notion section checks `GET /v1/users/me`)
- Modify: `docs/setup.md` (new §"Notion integration token": notion.so/profile/integrations → New integration → Internal, workspace; capabilities Read/Update/Insert content; grant pages `Second Brain` + `CSD EL` via each page's ⋯ → Connections; token → env file. §6 cloud allowlist gains `api.notion.com`.)
- Modify: `CLAUDE.md` (Secrets section gains `NOTION_TOKEN`; workspace-map quirks paragraph points reads at `scripts/notion.sh`)

- [ ] **Step 1: apply the three edits** (exact text in the executed diff; check-env Notion block):

```bash
echo "Notion:"
if [[ -n "${NOTION_TOKEN:-}" ]]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $NOTION_TOKEN" -H 'Notion-Version: 2025-09-03' \
    https://api.notion.com/v1/users/me)
  if [[ $code == 200 ]]; then ok "NOTION_TOKEN valid (GET /users/me → 200)"; else bad "NOTION_TOKEN rejected (→ $code)"; fi
else
  note "skipping Notion REST check (no NOTION_TOKEN)"
fi
note "Connector writes verified in-session (Stage 2 round-trip)."
```

- [ ] **Step 2: USER ACTION — Stanton creates the integration + grants pages + stores `NOTION_TOKEN`.** STOP and wait.
- [ ] **Step 3: verify + commit** — `check-env.sh` shows the Notion ✅; commit.

---

### Task 3: Finish the Stage 2 round-trip with structured tools

- [ ] **Step 1:** `notion.sh query <tasks-ds-id> '{"property":"Source ID","rich_text":{"equals":"manual-stage2-smoke"}}'` → exactly one result (the smoke task). Show Stanton.
- [ ] **Step 2:** `notion.sh archive <smoke-page-id>` → re-run the query → empty array. (Completes the DELETE leg the connector couldn't do.)
- [ ] **Step 3:** Stage 2 gate: Stanton eyeballs the Second Brain section + Rolling list view (with his manual snooze filter). Stage-completion commit.

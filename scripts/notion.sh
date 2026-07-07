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

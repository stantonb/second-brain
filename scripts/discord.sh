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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  : "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN must be set}"
  main "$@"
fi

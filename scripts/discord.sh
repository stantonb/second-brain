#!/usr/bin/env bash
# discord.sh — all Discord I/O for the second brain goes through here.
#
# Commands (message text is read from stdin where applicable):
#   send-dm                                DM $DISCORD_USER_ID (splits at 2000 chars)
#   send-channel <channel_id>              post to a channel (same splitting)
#   dm-channel                             print the DM channel id for $DISCORD_USER_ID
#   send-reminder [channel_id]             send ONE message (no splitting); print its id
#   fetch-captures <channel_id> [after_id] full paginated history after <after_id>
#                                          (default: from the start) as a JSON array,
#                                          oldest first
#   react <channel_id> <message_id> [emoji]  add a reaction (default ✅)
#   reactors <channel_id> <message_id> [emoji...]  user-ids that reacted (default ✅ 👍)
#
# Before each chunk is posted, send_channel checks the target channel's most
# recent message and skips the send if it's byte-identical and under
# DEDUPE_WINDOW seconds old — protects against a retried send re-posting the
# same non-idempotent message twice.
#
# Env: DISCORD_BOT_TOKEN (always), DISCORD_USER_ID (send-dm, dm-channel, and
#      send-reminder's DM fallback), DISCORD_API_BASE (test seam; default
#      https://discord.com/api/v10), DISCORD_DEDUPE_WINDOW (default 120).

API_BASE="${DISCORD_API_BASE:-https://discord.com/api/v10}"
MAX_LEN=2000
MAX_RETRIES=5
DEDUPE_WINDOW="${DISCORD_DEDUPE_WINDOW:-120}"

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

# recently_duplicate CHANNEL_ID CONTENT — true if the channel's most recent
# message is byte-identical to CONTENT and was posted within DEDUPE_WINDOW
# seconds. Guards a retried send (e.g. after a perceived failure that actually
# succeeded) from re-posting the same non-idempotent message twice.
recently_duplicate() {
  local channel_id=$1 content=$2 last ts epoch now
  last=$(discord_api GET "/channels/$channel_id/messages?limit=1") || return 1
  [[ $(jq 'length' <<<"$last") -eq 0 ]] && return 1
  jq -e --arg c "$content" '.[0].content == $c' <<<"$last" > /dev/null || return 1
  ts=$(jq -r '.[0].timestamp' <<<"$last")
  # Parse Discord's ISO-8601 timestamp with jq rather than `date -d` (GNU-only,
  # absent on BSD/macOS): drop fractional seconds and normalise a +00:00 offset
  # to Z so fromdateiso8601 accepts it. Fails safe (→ send) on any parse error.
  epoch=$(jq -rn --arg t "$ts" '$t | sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601') || return 1
  now=$(date +%s)
  (( now - epoch <= DEDUPE_WINDOW ))
}

# send_channel CHANNEL_ID — stdin → one or more POSTs (2000-char chunks).
send_channel() {
  local channel_id=$1 dir f content payload
  dir=$(mktemp -d)
  split_message "$dir"
  for f in "$dir"/chunk-*; do
    [[ -e $f ]] || { echo 'send_channel: empty message — nothing sent' >&2; break; }
    content=$(cat "$f")
    if recently_duplicate "$channel_id" "$content"; then
      echo "send_channel: identical message already posted in the last ${DEDUPE_WINDOW}s — skipping duplicate send" >&2
      continue
    fi
    payload=$(jq -c -Rs '{content: .}' "$f")
    discord_api POST "/channels/$channel_id/messages" "$payload" > /dev/null || { rm -rf "$dir"; return 1; }
  done
  rm -rf "$dir"
}

# dm_channel — prints the DM channel id for $DISCORD_USER_ID (opens/reuses it).
dm_channel() {
  discord_api POST '/users/@me/channels' \
    "{\"recipient_id\":\"$DISCORD_USER_ID\"}" | jq -r '.id'
}

# send_dm — stdin → DM to $DISCORD_USER_ID (opens/reuses the DM channel).
send_dm() {
  send_channel "$(dm_channel)"
}

# send_reminder [CHANNEL_ID] — stdin → ONE POST (no chunking); prints the created
# message id. No CHANNEL_ID → the DM channel. Used for individual reminder DMs whose
# id must be stored on the task for reaction-to-complete.
send_reminder() {
  local channel_id=${1:-} content payload
  content=$(cat)
  [[ -n $channel_id ]] || channel_id=$(dm_channel)
  payload=$(printf '%s' "$content" | jq -c -Rs '{content: .}')
  discord_api POST "/channels/$channel_id/messages" "$payload" | jq -r '.id'
}

# react CHANNEL_ID MESSAGE_ID [EMOJI] — default ✅. Empty body → Content-Length: 0.
react() {
  local channel_id=$1 message_id=$2 emoji=${3:-✅} encoded
  encoded=$(jq -rn --arg e "$emoji" '$e | @uri')
  discord_api PUT "/channels/$channel_id/messages/$message_id/reactions/$encoded/@me" '' > /dev/null
}

# reactors CHANNEL_ID MESSAGE_ID [EMOJI...] — prints a JSON array of the deduped user
# ids that reacted with any listed emoji (default ✅ 👍). One GET per emoji.
reactors() {
  local channel_id=$1 message_id=$2; shift 2
  local emojis=("$@") users='[]' e encoded resp
  (( ${#emojis[@]} )) || emojis=(✅ 👍)
  for e in "${emojis[@]}"; do
    encoded=$(jq -rn --arg x "$e" '$x | @uri')
    resp=$(discord_api GET \
      "/channels/$channel_id/messages/$message_id/reactions/$encoded?limit=100") || return 1
    users=$(jq -s '(.[0] + [.[1][].id]) | unique' <<<"$users$resp")
  done
  printf '%s\n' "$users"
}

usage() {
  cat >&2 <<'EOF'
usage: discord.sh <command>
  send-dm                                  DM $DISCORD_USER_ID (text on stdin)
  send-channel <channel_id>                post to channel (text on stdin)
  dm-channel                               print the DM channel id for $DISCORD_USER_ID
  send-reminder [channel_id]               send ONE message (text on stdin); print its id
  fetch-captures <channel_id> [after_id]   full history as JSON, oldest first
  react <channel_id> <message_id> [emoji]  add reaction (default ✅)
  reactors <channel_id> <message_id> [emoji...]  user-ids that reacted (default ✅ 👍)
EOF
  exit 2
}

main() {
  local cmd=${1:-}
  shift || true
  case $cmd in
    send-dm)        : "${DISCORD_USER_ID:?DISCORD_USER_ID must be set}"; send_dm ;;
    send-channel)   send_channel "${1:?usage: discord.sh send-channel <channel_id>}" ;;
    dm-channel)     : "${DISCORD_USER_ID:?DISCORD_USER_ID must be set}"; dm_channel ;;
    send-reminder)  send_reminder "${1:-}" ;;
    fetch-captures) fetch_captures "${1:?usage: discord.sh fetch-captures <channel_id> [after_id]}" "${2:-0}" ;;
    react)          react "${1:?channel_id required}" "${2:?message_id required}" "${3:-✅}" ;;
    reactors)       reactors "${1:?channel_id required}" "${2:?message_id required}" "${@:3}" ;;
    *)              usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  : "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN must be set}"
  main "$@"
fi

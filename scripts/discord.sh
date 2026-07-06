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

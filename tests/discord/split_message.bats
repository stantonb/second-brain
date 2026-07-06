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

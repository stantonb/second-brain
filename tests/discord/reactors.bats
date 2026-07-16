#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; }
teardown() { teardown_discord; }

@test "reactors unions reactors across the given emojis, deduped" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '[{"id":"U1"},{"id":"U2"}]' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '[{"id":"U2"},{"id":"U3"}]' > "$CURL_STUB_DIR/2.body"
  run reactors 555 1001 ✅ 👍
  [ "$status" -eq 0 ]
  [ "$(jq -c 'sort' <<<"$output")" = '["U1","U2","U3"]' ]
  [ "$(grep -c '%E2%9C%85' "$CURL_STUB_DIR/calls.log")" = "1" ]   # ✅
  [ "$(grep -c '%F0%9F%91%8D' "$CURL_STUB_DIR/calls.log")" = "1" ] # 👍
  [ "$(grep -c '/channels/555/messages/1001/reactions/' "$CURL_STUB_DIR/calls.log")" = "2" ]
}

@test "reactors defaults to the ✅/👍 allowlist when no emoji given" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '[]' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '[]' > "$CURL_STUB_DIR/2.body"
  run reactors 555 1001
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  [ "$(cat "$CURL_STUB_DIR/count")" = "2" ]
}

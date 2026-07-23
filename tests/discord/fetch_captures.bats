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
  [ "$(jq 'length' <<<"$output")" = "4" ]
  [ "$(jq -r '.[0].id' <<<"$output")" = "1391402271633244160" ]
  [ "$(jq -r '.[3].id' <<<"$output")" = "1391402271633244163" ]
  # cursor advanced to the newest id of each page
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=0')" = "1" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=1391402271633244161')" = "1" ]
  [ "$(sed -n '3p' "$CURL_STUB_DIR/calls.log" | grep -c 'after=1391402271633244163')" = "1" ]
}

@test "empty channel yields an empty JSON array" {
  cp "$FIX/captures-empty.json" "$CURL_STUB_DIR/1.body"; echo 200 > "$CURL_STUB_DIR/1.code"
  run fetch_captures 555
  [ "$status" -eq 0 ]
  [ "$(jq 'length' <<<"$output")" = "0" ]
}

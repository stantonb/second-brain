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

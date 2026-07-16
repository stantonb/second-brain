#!/usr/bin/env bats
load test_helper

setup()    { setup_discord; }
teardown() { teardown_discord; }

@test "send_channel splits long input into one POST per chunk" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '[]' > "$CURL_STUB_DIR/1.body"   # dedupe check, chunk 1
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '{}' > "$CURL_STUB_DIR/2.body"   # post, chunk 1
  echo 200 > "$CURL_STUB_DIR/3.code"; printf '[]' > "$CURL_STUB_DIR/3.body"   # dedupe check, chunk 2
  echo 200 > "$CURL_STUB_DIR/4.code"; printf '{}' > "$CURL_STUB_DIR/4.body"   # post, chunk 2
  line=$(head -c 1500 </dev/zero | tr '\0' 'a')
  printf '%s\n%s' "$line" "$line" | send_channel 555
  [ "$(cat "$CURL_STUB_DIR/count")" = "4" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.content | length')" = "1500" ]
  [ "$(grep -c '/channels/555/messages' "$CURL_STUB_DIR/calls.log")" = "4" ]
}

@test "send_channel skips a resend when the last message is an identical, recent duplicate" {
  echo 200 > "$CURL_STUB_DIR/1.code"
  now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
  printf '[{"content":"already sent","timestamp":"%s"}]' "$now" > "$CURL_STUB_DIR/1.body"
  printf 'already sent' | send_channel 555
  [ "$(cat "$CURL_STUB_DIR/count")" = "1" ]
}

@test "send_channel dedupe parses Discord's production timestamp format (.NNNNNN+00:00)" {
  echo 200 > "$CURL_STUB_DIR/1.code"
  now=$(date -u +%Y-%m-%dT%H:%M:%S.100000+00:00)
  printf '[{"content":"already sent","timestamp":"%s"}]' "$now" > "$CURL_STUB_DIR/1.body"
  printf 'already sent' | send_channel 555
  [ "$(cat "$CURL_STUB_DIR/count")" = "1" ]
}

@test "send_dm opens the DM channel then posts to it" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"999000"}' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '[]' > "$CURL_STUB_DIR/2.body"        # dedupe check
  echo 200 > "$CURL_STUB_DIR/3.code"; printf '{}' > "$CURL_STUB_DIR/3.body"        # post
  export DISCORD_USER_ID='111111111111111111'
  printf 'good morning' | send_dm
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/users/@me/channels')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.recipient_id')" = "111111111111111111" ]
  [ "$(sed -n '3p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/999000/messages')" = "1" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/payloads.log" | jq -r '.content')" = "good morning" ]
}

@test "react PUTs the URL-encoded ✅" {
  echo 204 > "$CURL_STUB_DIR/1.code"; : > "$CURL_STUB_DIR/1.body"
  run react 555 1001
  [ "$status" -eq 0 ]
  [ "$(grep -c '%E2%9C%85' "$CURL_STUB_DIR/calls.log")" = "1" ]
}

@test "dm_channel opens the DM channel and prints its id" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"DM1"}' > "$CURL_STUB_DIR/1.body"
  export DISCORD_USER_ID='111111111111111111'
  run dm_channel
  [ "$status" -eq 0 ]
  [ "$output" = "DM1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/users/@me/channels')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.recipient_id')" = "111111111111111111" ]
}

@test "send_reminder to a channel posts one message and prints its id" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"MSG777"}' > "$CURL_STUB_DIR/1.body"
  output=$(printf '⏰ Due today: Foo' | send_reminder 555); status=$?
  [ "$status" -eq 0 ]
  [ "$output" = "MSG777" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/555/messages')" = "1" ]
  [ "$(grep -c '/users/@me/channels' "$CURL_STUB_DIR/calls.log")" = "0" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.content')" = "⏰ Due today: Foo" ]
}

@test "send_reminder with no channel opens the DM then posts, printing the id" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{"id":"DM1"}'   > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/2.code"; printf '{"id":"MSG42"}' > "$CURL_STUB_DIR/2.body"
  export DISCORD_USER_ID='111111111111111111'
  output=$(printf 'hi' | send_reminder); status=$?
  [ "$status" -eq 0 ]
  [ "$output" = "MSG42" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/users/@me/channels')" = "1" ]
  [ "$(sed -n '2p' "$CURL_STUB_DIR/calls.log" | grep -c '/channels/DM1/messages')" = "1" ]
}

@test "CLI: unknown command prints usage and exits 2" {
  run bash scripts/discord.sh bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

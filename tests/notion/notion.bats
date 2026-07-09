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

@test "create_page POSTs parent data source + properties, no children by default" {
  echo 200 > "$CURL_STUB_DIR/1.code"
  printf '{"id":"new-page-1"}' > "$CURL_STUB_DIR/1.body"
  run create_page ds-123 '{"Name":{"title":[{"text":{"content":"evening-2026-07-09"}}]}}'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.id' <<<"$output")" = "new-page-1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.parent.type')" = "data_source_id" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.parent.data_source_id')" = "ds-123" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.properties.Name.title[0].text.content')" = "evening-2026-07-09" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq 'has("children")')" = "false" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c 'POST')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/pages')" = "1" ]
}

@test "create_page includes children blocks when given" {
  echo 200 > "$CURL_STUB_DIR/1.code"
  printf '{"id":"new-page-2"}' > "$CURL_STUB_DIR/1.body"
  run create_page ds-123 '{"Name":{"title":[]}}' '[{"object":"block","type":"paragraph","paragraph":{"rich_text":[{"text":{"content":"body line"}}]}}]'
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.children[0].paragraph.rich_text[0].text.content')" = "body line" ]
}

@test "create_page rejects malformed properties JSON without calling the API" {
  run create_page ds-123 'not-json'
  [ "$status" -ne 0 ]
  [ ! -f "$CURL_STUB_DIR/calls.log" ]
}

@test "update_props PATCHes page properties" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{}' > "$CURL_STUB_DIR/1.body"
  run update_props page-7 '{"Status":{"select":{"name":"Done"}}}'
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.properties.Status.select.name')" = "Done" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c 'PATCH')" = "1" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/pages/page-7')" = "1" ]
}

@test "append_blocks PATCHes children onto the page" {
  echo 200 > "$CURL_STUB_DIR/1.code"; printf '{}' > "$CURL_STUB_DIR/1.body"
  run append_blocks page-7 '[{"object":"block","type":"paragraph","paragraph":{"rich_text":[{"text":{"content":"rerun note"}}]}}]'
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/payloads.log" | jq -r '.children[0].paragraph.rich_text[0].text.content')" = "rerun note" ]
  [ "$(sed -n '1p' "$CURL_STUB_DIR/calls.log" | grep -c '/blocks/page-7/children')" = "1" ]
}

@test "CLI: unknown command prints usage and exits 2" {
  run bash scripts/notion.sh bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

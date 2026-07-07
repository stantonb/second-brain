# Shared setup for notion.sh bats tests. Reuses the discord curl/sleep stubs.
setup_notion() {
  CURL_STUB_DIR=$(mktemp -d)
  export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/../discord/stubs:$PATH"
  export NOTION_TOKEN='test-token'
  export NOTION_API_BASE='https://stub.invalid/v1'
  source "$BATS_TEST_DIRNAME/../../scripts/notion.sh"
}

teardown_notion() {
  rm -rf "$CURL_STUB_DIR"
}

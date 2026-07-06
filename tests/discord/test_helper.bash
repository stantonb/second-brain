# Shared setup for discord.sh bats tests.
setup_discord() {
  CURL_STUB_DIR=$(mktemp -d)
  export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  export DISCORD_BOT_TOKEN='test-token'
  export DISCORD_API_BASE='https://stub.invalid/api'
  source "$BATS_TEST_DIRNAME/../../scripts/discord.sh"
}

teardown_discord() {
  rm -rf "$CURL_STUB_DIR"
}

#!/usr/bin/env bats
# gh-prs.sh reads open PRs + CI state via curl/REST (the cloud host doesn't reliably
# provide the gh CLI). Reuses the discord curl stub: canned <n>.code/<n>.body replies,
# argv logged to calls.log.

setup() {
  CURL_STUB_DIR=$(mktemp -d)
  export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/../discord/stubs:$PATH"
  export GITHUB_API_BASE='https://stub.invalid/api'
  export GH_PAT='github_pat_default'
  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/gh-prs.sh"
}

teardown() { rm -rf "$CURL_STUB_DIR"; }

# One open PR authored by someone else with me as requested reviewer, and one of
# mine whose head sha has a failed check run.
fixture_pulls() {
  cat > "$CURL_STUB_DIR/1.body" <<'EOF'
[
  {"number": 7, "title": "Fix emails", "html_url": "https://x/7",
   "user": {"login": "colleague"},
   "requested_reviewers": [{"login": "stantonb"}],
   "head": {"sha": "aaa111"}},
  {"number": 9, "title": "My feature", "html_url": "https://x/9",
   "user": {"login": "stantonb"},
   "requested_reviewers": [],
   "head": {"sha": "bbb222"}}
]
EOF
  echo 200 > "$CURL_STUB_DIR/1.code"
  cat > "$CURL_STUB_DIR/2.body" <<'EOF'
{"check_runs": [{"status": "completed", "conclusion": "failure"},
                {"status": "completed", "conclusion": "success"}]}
EOF
  echo 200 > "$CURL_STUB_DIR/2.code"
}

@test "prs buckets review-requested and my PRs with CI state" {
  fixture_pulls
  run "$SCRIPT" prs stantonb/second-brain stantonb
  [ "$status" -eq 0 ]
  [ "$(jq -r '.needs_review[0].number' <<<"$output")" = "7" ]
  [ "$(jq -r '.needs_review | length' <<<"$output")" = "1" ]
  [ "$(jq -r '.mine[0].number' <<<"$output")" = "9" ]
  [ "$(jq -r '.mine[0].ci' <<<"$output")" = "failure" ]
}

@test "prs reports ci success when all check runs pass" {
  fixture_pulls
  cat > "$CURL_STUB_DIR/2.body" <<'EOF'
{"check_runs": [{"status": "completed", "conclusion": "success"}]}
EOF
  run "$SCRIPT" prs stantonb/second-brain stantonb
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mine[0].ci' <<<"$output")" = "success" ]
}

@test "prs reports ci none when a PR has no check runs" {
  fixture_pulls
  printf '{"check_runs": []}' > "$CURL_STUB_DIR/2.body"
  run "$SCRIPT" prs stantonb/second-brain stantonb
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mine[0].ci' <<<"$output")" = "none" ]
}

@test "prs authenticates with the per-owner GH_PAT_<OWNER> override" {
  export GH_PAT_LIKENESS_MARKET='github_pat_org'
  printf '[]' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/1.code"
  run "$SCRIPT" prs Likeness-Market/MarketPlace stantonb
  [ "$status" -eq 0 ]
  grep -q 'Bearer github_pat_org' "$CURL_STUB_DIR/calls.log"
  ! grep -q 'Bearer github_pat_default' "$CURL_STUB_DIR/calls.log"
}

@test "prs fails non-zero on a non-2xx pulls response" {
  echo 404 > "$CURL_STUB_DIR/1.code"
  printf '{"message":"Not Found"}' > "$CURL_STUB_DIR/1.body"
  run "$SCRIPT" prs stantonb/NoSuchRepo stantonb
  [ "$status" -ne 0 ]
}

@test "prs resolves the username via /user when not given, and reports pending CI" {
  # call order: 1=/user, 2=pulls, 3=check-runs
  printf '{"login": "stantonb"}' > "$CURL_STUB_DIR/1.body"
  echo 200 > "$CURL_STUB_DIR/1.code"
  cat > "$CURL_STUB_DIR/2.body" <<'EOF'
[
  {"number": 9, "title": "My feature", "html_url": "https://x/9",
   "user": {"login": "stantonb"},
   "requested_reviewers": [],
   "head": {"sha": "bbb222"}}
]
EOF
  echo 200 > "$CURL_STUB_DIR/2.code"
  printf '{"check_runs": [{"status": "in_progress", "conclusion": null}]}' > "$CURL_STUB_DIR/3.body"
  echo 200 > "$CURL_STUB_DIR/3.code"
  run "$SCRIPT" prs stantonb/second-brain
  [ "$status" -eq 0 ]
  [ "$(jq -r '.mine[0].ci' <<<"$output")" = "pending" ]
}

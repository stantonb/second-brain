#!/usr/bin/env bats
# gh-token.sh resolves the effective GitHub token — preferring GH_PAT (our fine-grained
# PAT) over a platform-injected, repo-scoped GH_TOKEN — and labels the token type WITHOUT
# ever printing the secret. Pure env logic: no network, no stubs.

SCRIPT="$BATS_TEST_DIRNAME/../../scripts/gh-token.sh"

@test "GH_PAT overrides a platform-injected GH_TOKEN" {
  run bash -c "export GH_PAT='github_pat_mine' GH_TOKEN='ghs_platform'; source '$SCRIPT'; printf '%s' \"\$GH_TOKEN\""
  [ "$status" -eq 0 ]
  [ "$output" = "github_pat_mine" ]
}

@test "with no GH_PAT, GH_TOKEN is left unchanged (local fallback)" {
  run bash -c "unset GH_PAT; export GH_TOKEN='github_pat_local'; source '$SCRIPT'; printf '%s' \"\$GH_TOKEN\""
  [ "$status" -eq 0 ]
  [ "$output" = "github_pat_local" ]
}

@test "gh_token_kind labels a fine-grained PAT" {
  run bash -c "export GH_TOKEN='github_pat_abc'; source '$SCRIPT'; gh_token_kind"
  [ "$status" -eq 0 ]
  [ "$output" = "fine-grained PAT" ]
}

@test "gh_token_kind flags an installation/app token (the platform proxy)" {
  run bash -c "unset GH_PAT; export GH_TOKEN='ghs_installationxyz'; source '$SCRIPT'; gh_token_kind"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installation"* ]]
}

@test "gh_token_kind never prints the token value" {
  run bash -c "export GH_TOKEN='github_pat_SUPERSECRET'; source '$SCRIPT'; gh_token_kind"
  [ "$status" -eq 0 ]
  [[ "$output" != *"SUPERSECRET"* ]]
}

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

@test "with no GH_PAT, a pre-existing GH_TOKEN is left untouched (never clobbered)" {
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

@test "gh_token_for prefers a per-owner GH_PAT_<OWNER> override" {
  run bash -c "export GH_TOKEN='github_pat_default' GH_PAT_LIKENESS_MARKET='github_pat_org'; source '$SCRIPT'; gh_token_for 'Likeness-Market/MarketPlace'"
  [ "$status" -eq 0 ]
  [ "$output" = "github_pat_org" ]
}

# &&-chained assertions: this machine's bats (bash 3.2) only registers the final
# command's status, so independent assertion lines can false-pass.
@test "gh_token_for falls back to GH_PAT when no per-owner override exists" {
  run bash -c "export GH_PAT='github_pat_mine' GH_TOKEN='ghs_platform'; source '$SCRIPT'; gh_token_for 'stantonb/second-brain'"
  [ "$status" -eq 0 ] && [ "$output" = "github_pat_mine" ]
}

@test "gh_token_for never returns a platform GH_TOKEN (empty when no PAT is set)" {
  run bash -c "unset GH_PAT; export GH_TOKEN='ghs_platform'; source '$SCRIPT'; gh_token_for 'stantonb/second-brain'"
  [ "$status" -eq 0 ] && [ "$output" = "" ]
}

@test "gh_token_kind labels an explicit token argument without printing it" {
  run bash -c "unset GH_PAT GH_TOKEN; source '$SCRIPT'; gh_token_kind 'ghs_installationSECRET'"
  [ "$status" -eq 0 ] &&
    [[ "$output" == *"installation"* ]] &&
    [[ "$output" != *"SECRET"* ]]
}

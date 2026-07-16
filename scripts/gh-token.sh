#!/usr/bin/env bash
# gh-token.sh — resolve the effective GitHub token for `gh`/api.github.com calls.
#
# WHY: on the cloud routine host, GitHub access via `GH_TOKEN` behaves as if scoped to the
# single bound repo (`second-brain`) — the briefing's GitHub section then ⚠️s on the other
# allowlisted repos, even though our fine-grained PAT can see them all locally. The robust
# fix is to store the PAT under a name the platform does not set — GH_PAT — and prefer it:
# exporting GH_TOKEN=$GH_PAT here makes `gh`/curl use our PAT regardless of any
# platform-injected GH_TOKEN/GITHUB_TOKEN (GH_TOKEN wins gh's precedence). Local runs, where
# only GH_TOKEN is set, are unaffected (GH_PAT unset → GH_TOKEN left as-is).
#
# Usage: `. scripts/gh-token.sh` (source) before any GitHub call. Never prints token values.

if [[ -n "${GH_PAT:-}" ]]; then
  export GH_TOKEN="$GH_PAT"
fi

# gh_token_for OWNER/REPO — print the token to use for GitHub calls against this repo:
# a per-owner override GH_PAT_<OWNER> (owner uppercased, non-alphanumerics → _) if set,
# else the effective GH_TOKEN. A fine-grained PAT has exactly ONE resource owner, so a
# repo owned by another user/org (e.g. Likeness-Market/MarketPlace) can never be granted
# on the stantonb PAT — it needs its own PAT, stored e.g. as GH_PAT_LIKENESS_MARKET.
# Usage: GH_TOKEN=$(gh_token_for "$repo") gh pr list --repo "$repo" ...
gh_token_for() {
  local owner=${1%%/*} var
  var="GH_PAT_$(printf '%s' "$owner" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
  printf '%s' "${!var:-${GH_TOKEN:-}}"
}

# gh_token_kind — echo a secret-safe label for the effective GH_TOKEN's type, derived from
# its public format prefix only (never the value). Lets check-env/diagnostics show whether
# the effective token is our PAT or a platform installation token, without leaking it.
gh_token_kind() {
  case "${GH_TOKEN:-}" in
    github_pat_*) echo "fine-grained PAT" ;;
    ghp_*)        echo "classic PAT" ;;
    ghs_*)        echo "installation/app token (platform-injected?)" ;;
    gho_*)        echo "OAuth token" ;;
    "")           echo "unset" ;;
    *)            echo "unknown type" ;;
  esac
}

#!/usr/bin/env bash
# gh-token.sh — resolve the effective GitHub token for api.github.com calls.
#
# THE STANDARD (2026-07-17): `GH_PAT` (+ per-owner `GH_PAT_<OWNER>`) are the ONLY GitHub
# secrets we store — in the local env file and the cloud env alike. `GH_TOKEN` is NEVER
# stored: the cloud routine host injects its own repo-scoped GH_TOKEN at runtime (it sees
# only the bound `second-brain` repo and would ⚠️ every other allowlisted repo), so our
# secret must live under a name the platform does not set. Exporting GH_TOKEN=$GH_PAT here
# derives the effective token for anything that reads GH_TOKEN, regardless of any
# platform-injected value. A pre-existing GH_TOKEN with no GH_PAT is left untouched
# (nothing to prefer) — check-env flags that setup as non-standard.
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

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

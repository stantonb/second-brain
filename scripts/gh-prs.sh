#!/usr/bin/env bash
# gh-prs.sh — the briefing's GitHub PR/CI reads, via curl + the REST API.
# Exists because the cloud routine host does not reliably provide the `gh` CLI
# (2026-07-17 morning run: absent → the GitHub section could only ⚠️), and every
# other integration already goes through a curl-based script. The token is
# resolved PER REPO via gh-token.sh (`GH_PAT`, or `GH_PAT_<OWNER>` for repos
# owned by another user/org — fine-grained PATs are single-owner).
#
# Commands:
#   prs <owner/repo> [username]   print one JSON object:
#       {"repo": "...",
#        "needs_review": [{number,title,url}],           PRs awaiting my review
#        "mine":         [{number,title,url,ci}]}        my open PRs
#     ci ∈ success | failure | pending | none (no check runs on the head sha).
#     [username] defaults to the token's own login (GET /user).
#
# Env: GH_PAT / GH_PAT_<OWNER> (via gh-token.sh), GITHUB_API_BASE (test seam;
#      default https://api.github.com). Never prints token values.
set -uo pipefail

API_BASE="${GITHUB_API_BASE:-https://api.github.com}"

source "$(dirname "$0")/gh-token.sh"

# gh_api TOKEN PATH — prints the response body; non-2xx → diagnostic line on stderr,
# rc 1. The diagnostic carries GitHub's error message, the token's format kind, and
# whether an x-github-request-id header came back (a real-GitHub response always has
# one; an intermediary's synthetic response usually doesn't) — never the token itself.
# GitHub's message text is the discriminator the 2026-07-17..20 403s were missing:
# "…not accessible by integration" = a platform app token was evaluated, not our PAT.
gh_api() {
  local token=$1 path=$2 hdrs resp code body msg reqid=absent
  hdrs=$(mktemp)
  resp=$(curl -sS -D "$hdrs" -w $'\n%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.github+json' \
    "$API_BASE$path")
  code=${resp##*$'\n'}
  body=${resp%$'\n'*}
  if [[ $code == 2* ]]; then
    rm -f "$hdrs"
    printf '%s' "$body"
    return 0
  fi
  grep -qi '^x-github-request-id:' "$hdrs" && reqid=present
  rm -f "$hdrs"
  msg=$(jq -r '.message? // empty' <<<"$body" 2>/dev/null)
  echo "gh_api: GET $path → HTTP $code (${msg:-no message}; token: $(gh_token_kind "$token"); github-request-id: $reqid)" >&2
  return 1
}

# prs OWNER/REPO [USERNAME] — see header.
prs() {
  local repo=$1 user=${2:-} token pulls mine_shas sha runs ci
  token=$(gh_token_for "$repo")
  if [[ -z $token ]]; then
    echo "gh-prs: no GH_PAT (or GH_PAT_<OWNER> override) set for $repo — refusing to fall back to a platform-injected GH_TOKEN; GitHub reads use our PAT only" >&2
    return 1
  fi
  if [[ -z $user ]]; then
    user=$(gh_api "$token" "/user" | jq -r '.login') || return 1
  fi
  pulls=$(gh_api "$token" "/repos/$repo/pulls?state=open&per_page=100") || return 1

  # CI state per my-PR head sha, joined back in jq afterwards.
  local ci_map='{}'
  while IFS= read -r sha; do
    [[ -n $sha ]] || continue
    runs=$(gh_api "$token" "/repos/$repo/commits/$sha/check-runs") || return 1
    ci=$(jq -r '.check_runs
      | if length == 0 then "none"
        elif any(.[]; .conclusion == "failure") then "failure"
        elif any(.[]; .status != "completed") then "pending"
        else "success" end' <<<"$runs")
    ci_map=$(jq -c --arg s "$sha" --arg ci "$ci" '. + {($s): $ci}' <<<"$ci_map")
  done < <(jq -r --arg u "$user" '.[] | select(.user.login == $u) | .head.sha' <<<"$pulls")

  jq -c --arg u "$user" --arg repo "$repo" --argjson ci "$ci_map" '{
    repo: $repo,
    needs_review: [ .[] | select(any(.requested_reviewers[]?; .login == $u))
                    | {number, title, url: .html_url} ],
    mine:         [ .[] | select(.user.login == $u)
                    | {number, title, url: .html_url, ci: $ci[.head.sha]} ]
  }' <<<"$pulls"
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

main() {
  case "${1:-}" in
    prs) [[ $# -ge 2 ]] || usage; prs "$2" "${3:-}" ;;
    *)   usage ;;
  esac
}

# Execute only when run directly (sourcing gets the functions, as in tests/check-env).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

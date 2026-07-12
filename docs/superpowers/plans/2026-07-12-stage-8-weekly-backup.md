# Stage 8 — Weekly Notion Backup Implementation Plan ✋ CHECKPOINT STAGE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (Stanton pre-selected inline execution for this project.)

**Goal:** The weekly-review routine exports the Second Brain databases + Brag doc to `backups/` and commits them **straight to `main`**, so the brain's state is versioned in git and restorable if Notion is ever lost.

**Architecture:** A TDD'd `scripts/notion-backup.sh` reuses `notion.sh`'s `query_db`/`notion_api` (source-and-reuse, no duplication): it queries each of the four databases with full pagination → sorted JSON arrays under `backups/`, and fetches the Brag doc page's blocks → `backups/brag-doc.json`. Sorting by page id keeps weekly `git diff`s meaningful. The weekly-review skill runs it **production only** (fixture/dry-run never commit), then commits + `git push origin HEAD:main`. Stanton chose direct-to-`main` (spec note 2026-07-12), so the repo's **"Allow unrestricted branch pushes"** toggle is enabled for the routine.

**Tech Stack:** bash, curl, jq, bats, `scripts/notion.sh`, git, claude.ai routine with unrestricted push permission.

## Global Constraints

- Spec is source of truth: `docs/superpowers/specs/2026-07-06-second-brain-design.md` (Phase 2 item 3 + the 2026-07-12 surface-verification note recording the direct-to-`main` choice). Reality contradicts it → STOP and ask Stanton; record with a dated note.
- Secrets only in cloud env vars + local shell. Backups contain **only Second Brain data** (Tasks/Journal/Capture Log/Reading list/Brag doc) — never secrets, never `CSD EL`, `Habit Tracker`, or `DND`.
- Notion **reads** for the backup go via `scripts/notion.sh` REST (full pagination, never partial). No writes to Notion at all in this stage.
- Rule #1 — never fail silent: a backup or push failure must **not** abort the weekly review — it adds a ⚠️ line to the DM and the review still delivers.
- TDD for `notion-backup.sh`.
- Anything only Stanton can do on the personal account (routine push permission, cloud env) is a **USER-ACTION** with exact instructions, then STOP.
- ✋ **CHECKPOINT:** a real production weekly run commits an updated backup to `main`, verified on `origin/main`, then STOP for Stanton's confirmation before Stage 9.
- Commit after each task.

**Prerequisite:** Core complete (Stages 0–5); Phase 2 planning gate open; data source IDs + Brag doc page ID present in `CLAUDE.md`. **Execution waits for Stanton's explicit go and the reliability bar.**

---

### Task 1: TDD `scripts/notion-backup.sh`

**Files:**
- Create: `tests/fixtures/notion/blocks-page-1.json`, `tests/fixtures/notion/blocks-page-2.json`, `tests/fixtures/notion/list-single.json`
- Create: `tests/notion/notion-backup.bats`
- Create: `scripts/notion-backup.sh`

**Interfaces:**
- Consumes: `scripts/notion.sh` functions `query_db`, `notion_api` (sourced).
- Produces: `backup_datasource DS_ID OUTFILE`, `backup_page PAGE_ID OUTFILE`, `fetch_block_children BLOCK_ID`, `backup_all OUTDIR`; CLI `notion-backup.sh run [outdir]`. Consumed by the weekly-review skill.

- [ ] **Step 1: Write the block-children fixtures.** `tests/fixtures/notion/blocks-page-1.json`:

```json
{ "object": "list", "results": [ { "id": "b1" }, { "id": "b2" } ],
  "has_more": true, "next_cursor": "cur-2" }
```

`tests/fixtures/notion/blocks-page-2.json`:

```json
{ "object": "list", "results": [ { "id": "b3" } ],
  "has_more": false, "next_cursor": null }
```

`tests/fixtures/notion/list-single.json`:

```json
{ "object": "list", "results": [ { "id": "x1" } ], "has_more": false, "next_cursor": null }
```

- [ ] **Step 2: Write the failing tests — `tests/notion/notion-backup.bats`** (reuses the shared discord curl stub, same seam as `notion.bats`):

```bash
#!/usr/bin/env bats

setup() {
  CURL_STUB_DIR=$(mktemp -d); export CURL_STUB_DIR
  export PATH="$BATS_TEST_DIRNAME/../discord/stubs:$PATH"
  export NOTION_TOKEN='test-token'
  export NOTION_API_BASE='https://stub.invalid/v1'
  source "$BATS_TEST_DIRNAME/../../scripts/notion-backup.sh"
  FIX="$BATS_TEST_DIRNAME/../fixtures/notion"
  OUT=$(mktemp -d)
}
teardown() { rm -rf "$CURL_STUB_DIR" "$OUT"; }

@test "backup_datasource writes a JSON array of all pages (paginated)" {
  cp "$FIX/query-page-1.json" "$CURL_STUB_DIR/1.body"; echo 200 > "$CURL_STUB_DIR/1.code"
  cp "$FIX/query-page-2.json" "$CURL_STUB_DIR/2.body"; echo 200 > "$CURL_STUB_DIR/2.code"
  run backup_datasource ds-123 "$OUT/tasks.json"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' "$OUT/tasks.json")" = "3" ]
  [ "$(jq -r '.[2].id' "$OUT/tasks.json")" = "t3" ]
}

@test "backup_page paginates block children into a JSON array" {
  cp "$FIX/blocks-page-1.json" "$CURL_STUB_DIR/1.body"; echo 200 > "$CURL_STUB_DIR/1.code"
  cp "$FIX/blocks-page-2.json" "$CURL_STUB_DIR/2.body"; echo 200 > "$CURL_STUB_DIR/2.code"
  run backup_page brag-1 "$OUT/brag-doc.json"
  [ "$status" -eq 0 ]
  [ "$(jq 'length' "$OUT/brag-doc.json")" = "3" ]
  [ "$(jq -r '.[2].id' "$OUT/brag-doc.json")" = "b3" ]
  [ "$(grep -c '/blocks/brag-1/children' "$CURL_STUB_DIR/calls.log")" -ge "1" ]
  [ "$(grep -c 'start_cursor=cur-2' "$CURL_STUB_DIR/calls.log")" = "1" ]
}

@test "backup_all writes one file per database plus brag-doc.json" {
  for i in 1 2 3 4 5; do cp "$FIX/list-single.json" "$CURL_STUB_DIR/$i.body"; done
  run backup_all "$OUT"
  [ "$status" -eq 0 ]
  for f in tasks journal capture-log reading-list brag-doc; do
    [ -f "$OUT/$f.json" ] || { echo "missing $f.json"; false; }
  done
}

@test "CLI: unknown command prints usage and exits 2" {
  run bash scripts/notion-backup.sh bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
```

- [ ] **Step 3: Run to verify failure** — `bats tests/notion/notion-backup.bats` → `No such file` (notion-backup.sh missing).

- [ ] **Step 4: Implement `scripts/notion-backup.sh`**

```bash
#!/usr/bin/env bash
# notion-backup.sh — export the Second Brain databases + Brag doc to a directory of JSON
# files, for the weekly git-committed backup (spec Phase 2 item 3). Reuses notion.sh's
# REST reads (query_db / notion_api); adds nothing to Notion. Reads only — never writes
# Notion, never touches CSD EL / Habit Tracker / DND.
#
# Commands:
#   run [outdir]   export everything to outdir (default: backups)
#
# Env: NOTION_TOKEN (required, via notion.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/notion.sh
source "$SCRIPT_DIR/notion.sh"   # defines notion_api, query_db (main() guarded — not run)

# Manifest: "name data_source_id" per line. IDs mirror CLAUDE.md's Data source table
# (CLAUDE.md is the source of truth — update both together if a database is added).
BACKUP_MANIFEST='tasks 01e1c068-5703-423a-b910-f4bd5644e4ab
journal a2dd6ff2-6131-49d1-943c-3fcfe6b15d0d
capture-log 83a1f8af-290f-4bea-aa51-c2f2e74c8e76
reading-list 103ccd0e-302f-4485-b737-a400a37f65a0'
BACKUP_BRAG_PAGE='396edd10-0411-8199-b42a-e57f361b5242'

# fetch_block_children BLOCK_ID — JSON array of a page/block's direct children,
# following has_more/next_cursor to the end (mirrors query_db's pagination for GET).
fetch_block_children() {
  local block_id=$1 cursor='' combined='[]' page has_more path
  while :; do
    path="/blocks/$block_id/children?page_size=100"
    [[ -n $cursor ]] && path="$path&start_cursor=$cursor"
    page=$(notion_api GET "$path") || return 1
    combined=$(jq -s '.[0] + .[1].results' <<<"$combined$page")
    has_more=$(jq -r '.has_more' <<<"$page")
    [[ $has_more != true ]] && break
    cursor=$(jq -r '.next_cursor' <<<"$page")
  done
  printf '%s\n' "$combined"
}

# backup_datasource DS_ID OUTFILE — full DB dump, sorted by page id for clean diffs.
backup_datasource() {
  local ds=$1 out=$2
  query_db "$ds" | jq 'sort_by(.id)' > "$out"
}

# backup_page PAGE_ID OUTFILE — the page's top-level blocks, sorted by id.
backup_page() {
  local page=$1 out=$2
  fetch_block_children "$page" | jq 'sort_by(.id)' > "$out"
}

# backup_all OUTDIR — every database file + brag-doc.json.
backup_all() {
  local outdir=$1 name ds
  mkdir -p "$outdir"
  while read -r name ds; do
    [[ -z $name ]] && continue
    backup_datasource "$ds" "$outdir/$name.json" || return 1
  done <<< "$BACKUP_MANIFEST"
  backup_page "$BACKUP_BRAG_PAGE" "$outdir/brag-doc.json" || return 1
}

usage() {
  cat >&2 <<'EOF'
usage: notion-backup.sh run [outdir]
  run [outdir]   export all Second Brain databases + Brag doc to outdir (default: backups)
EOF
  exit 2
}

main() {
  local cmd=${1:-}
  case $cmd in
    run) backup_all "${2:-backups}" ;;
    *)   usage ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  : "${NOTION_TOKEN:?NOTION_TOKEN must be set}"
  main "$@"
fi
```

- [ ] **Step 5: Run to verify pass** — `chmod +x scripts/notion-backup.sh && bats tests/notion/notion-backup.bats` → `4 tests, 0 failures`. Then `bats -r tests/` → all green (previous total + 4).
- [ ] **Step 6: Commit**

```bash
git add scripts/notion-backup.sh tests/notion/notion-backup.bats tests/fixtures/notion/blocks-page-1.json tests/fixtures/notion/blocks-page-2.json tests/fixtures/notion/list-single.json
git commit -m "feat: notion-backup.sh — export Second Brain DBs + Brag doc (TDD)"
```

---

### Task 2: Wire the backup into the weekly-review skill

**Files:**
- Create: `backups/README.md`
- Modify: `.claude/skills/weekly-review/SKILL.md`
- Modify: `CLAUDE.md` (Notion access split paragraph — note the backup)

**Interfaces:**
- Consumes: `scripts/notion-backup.sh run backups` from Task 1.
- Produces: a production-only weekly commit of `backups/` to `main`.

- [ ] **Step 1: Write `backups/README.md`** (creates the directory + documents it):

```markdown
# Backups

Weekly snapshots of the Second Brain Notion databases, written by the weekly-review
routine (`scripts/notion-backup.sh run backups`) and committed to `main`.

- `tasks.json`, `journal.json`, `capture-log.json`, `reading-list.json` — full page
  arrays from each database (REST `data_sources/{id}/query`, all pages, sorted by id).
- `brag-doc.json` — the Brag doc page's top-level blocks.

Files are overwritten each week; `git log` / `git diff` is the version history. To
restore, read these back into Notion. Data source IDs live in `CLAUDE.md` (source of
truth). Contains Second Brain data only — never secrets, never CSD EL / Habit Tracker / DND.
```

- [ ] **Step 2: Edit `.claude/skills/weekly-review/SKILL.md`.** Insert a new step **immediately after the `Gather` step and before the `Compose` step** (so a failure is surfaced in the DM), then renumber the following steps (Compose, Brag append, Self-check, Deliver+journal, and the Stage-7 dead-man's-switch ping) so numbering stays sequential. The new step:

```markdown
2. **Weekly backup (production only; skip in FIXTURE_MODE and DRY_RUN — in DRY_RUN report
   "would back up + push" instead).** Version the brain's state in git:
   - Export: `./scripts/notion-backup.sh run backups`
   - Stage: `git add backups/`
   - If `git diff --cached --quiet backups/` → nothing changed this week; skip the commit.
   - Else commit and push straight to `main` (the repo has "Allow unrestricted branch
     pushes" enabled — Stage 8):
     `git -c user.name='second-brain' -c user.email='second-brain@users.noreply.github.com' commit -m "chore(backup): Second Brain snapshot $TODAY"`
     then `git push origin HEAD:main`.
   - Rule #1: a backup or push failure must **not** abort the review. On any error,
     capture a `⚠️ couldn't complete weekly backup ({reason})` line and append it to the
     composed DM before delivering; then carry on.
```

- [ ] **Step 3: Edit `CLAUDE.md`** — append to the end of the **Notion access split** paragraph:

```markdown
`scripts/notion-backup.sh run backups` exports the four databases + Brag doc (REST reads
only) to `backups/`; the weekly routine commits that snapshot straight to `main`
(unrestricted branch pushes enabled 2026-07-12, Stanton's choice — spec note same date).
```

- [ ] **Step 4: Commit**

```bash
git add backups/README.md .claude/skills/weekly-review/SKILL.md CLAUDE.md
git commit -m "feat: weekly-review commits a Notion backup to main (production only)"
```

---

### Task 3: Local end-to-end backup against live Notion

**Files:**
- Create (generated): `backups/tasks.json`, `backups/journal.json`, `backups/capture-log.json`, `backups/reading-list.json`, `backups/brag-doc.json`

- [ ] **Step 1: Run the real export locally** (Stanton's local `NOTION_TOKEN`, work Claude session): `bash -c 'source ~/.config/second-brain/env && ./scripts/notion-backup.sh run backups'`.
- [ ] **Step 2: Verify the output (evidence, show Stanton):**
  - Five files exist under `backups/`, each valid JSON (`jq -e . backups/*.json > /dev/null && echo OK`).
  - Row counts are sane: `for f in tasks journal capture-log reading-list; do echo "$f: $(jq 'length' backups/$f.json)"; done` — compare against what he sees in Notion (e.g. Journal length ≈ number of run pages so far).
  - `backups/brag-doc.json` contains the month heading(s) + bullets the weekly review has appended.
  - No secret material anywhere: `grep -riE 'token|secret|Bearer' backups/ || echo "clean"`.
- [ ] **Step 3: Commit the first real snapshot**

```bash
git add backups/*.json
git commit -m "chore(backup): first Second Brain snapshot"
```

---

### Task 4: USER-ACTION — enable direct pushes on the routine

**Files:** none (personal-account UI).

- [ ] **Step 1: USER ACTION — Stanton**, at claude.ai → Claude Code → the `weekly-review` routine (or the repo's cloud environment) → **Permissions**, enables **"Allow unrestricted branch pushes"** for `stantonb/second-brain`, so the routine can `git push origin HEAD:main`. Confirm the routine's GitHub mount has **write/push** permission to the repo (not read-only). **STOP and wait for confirmation.**
- [ ] **Step 2: Push all commits to `main`** so the routine clones a remote that already contains `notion-backup.sh`, the updated skill, and `backups/`.

---

### Task 5: ✋ CHECKPOINT — a real weekly run backs up to main

**Files:** none.

- [ ] **Step 1: Trigger one manual production run of `weekly-review`** (Run now — a mid-week run is fine; the self-check reports a partial week honestly). Verify:
  - The DM + `weekly-<today>` Journal page still land (backup must be additive).
  - A **new commit appears on `origin/main`** authored `second-brain`, titled `chore(backup): Second Brain snapshot <date>`, touching only `backups/*.json` (`git fetch && git log origin/main -1 --stat`).
  - The backup JSON reflects current Notion (spot-check one changed value vs. Notion).
  - If nothing changed since Task 3's snapshot, confirm the run correctly **skipped** the commit (no empty commit) — re-run after making a small Notion change to see a real diff.
- [ ] **Step 2:** Confirm the failure path is safe: if the push were rejected (e.g. toggle off), the review would still deliver its DM with a `⚠️ couldn't complete weekly backup` line — Stanton can reason about this from the skill text; no need to force a real failure.
- [ ] **Step 3: STOP.** Ask Stanton explicitly: "Weekly backups are committing to `main` and the review is unaffected — happy to close Stage 8? Stage 9 (`meeting:` pipeline) starts only on your word." Wait for confirmation.
- [ ] **Step 4: Stage-completion commit**

```bash
git add -A
git commit -m "chore: complete Stage 8 — weekly Notion backup commits to main" --allow-empty
```

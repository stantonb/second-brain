# Fixtures

Canned service data. Two consumers:

1. **bats tests** — the curl stub replays the Discord pages to test pagination.
2. **`FIXTURE_MODE=1` skill runs** — skills read these files *instead of* live services
   (no network, no Notion writes) and print the composed briefing plus a "Would write:"
   list of every mutation that production would have made.

Mapping used by skills in fixture mode:

| Live source | Fixture |
|---|---|
| `discord.sh fetch-captures` | `discord/captures-page-1.json` + `discord/captures-page-2.json` (concatenated, oldest first) |
| Notion Tasks DB rolling-list query | `notion/tasks.json` |
| GitHub `gh pr list` per allowlist repo | `github/prs.json` |
| Google Calendar (today) | `google/calendar-today.json` (from Stage 3) |
| Gmail triage | `google/gmail.json` (from Stage 3) |
| Notion Journal week query | `notion/journal-week.json` (from Stage 5) |
| CSD EL recently-updated sub-pages | `notion/csd-el-recent.json` (from Stage 5) |

Dates inside fixtures are fixed (early July 2026); age-dependent assertions are written
as "older than 14 days", which stays true at any later run date.

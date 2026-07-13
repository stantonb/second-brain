# Setup runbook

Everything a human must click to stand up the second brain. Machine-side validation:
`scripts/check-env.sh`. Secrets go in `~/.config/second-brain/env` (§4) — never in this repo.

## 1. Discord server, channels, bot

### 1.1 Server + channels
1. Discord app → **+** (Add a Server) → **Create My Own** → **For me and my friends** →
   name: `Second Brain` → Create.
2. Create two text channels: right-click the server name → **Create Channel** → Text →
   `capture`, then again → `test`.
3. Enable Developer Mode: **User Settings → Advanced → Developer Mode** ON.
4. Right-click **#capture** → **Copy Channel ID** → this is `DISCORD_CAPTURE_CHANNEL_ID`.
5. Right-click **#test** → **Copy Channel ID** → `DISCORD_TEST_CHANNEL_ID`.
6. Right-click your own name in the member list → **Copy User ID** → `DISCORD_USER_ID`.

### 1.2 Bot application
1. <https://discord.com/developers/applications> → **New Application** → name
   `second-brain` → Create.
2. Sidebar → **Bot**:
   - **Reset Token** → copy the token → `DISCORD_BOT_TOKEN`. It is shown once — store it
     in §4's file immediately. Never paste it into chat, logs, or the repo.
   - **Privileged Gateway Intents** → toggle **MESSAGE CONTENT INTENT** ON → Save.
3. Sidebar → **OAuth2** → **URL Generator**:
   - Scopes: `bot`.
   - Bot Permissions: **View Channels**, **Send Messages**, **Read Message History**,
     **Add Reactions**.
   - Copy the generated URL, open it in a browser, choose the **Second Brain** server,
     **Authorise**.
4. Confirm in Discord: the bot appears in the member list and can see #capture and #test.

## 2. GitHub fine-grained PAT

1. Decide the **repo allowlist** — the exact repos the morning briefing watches for PRs/CI.
   These go in `CLAUDE.md → ## GitHub repo allowlist` (Stage 1) and the PAT is scoped to match.
2. <https://github.com/settings/personal-access-tokens/new>:
   - Token name: `second-brain`. Expiration: 90 days (set a renewal reminder).
   - Resource owner: the owner of the allowlist repos. **Note:** repos owned by an
     organisation (e.g. `simplybusiness`) require that org to permit fine-grained PATs —
     if the org isn't offered as resource owner or the token is rejected, that's an IT
     conversation; until resolved, keep only personal repos in the allowlist.
   - Repository access: **Only select repositories** → pick exactly the allowlist repos.
   - Repository permissions: **Pull requests: Read-only**, **Contents: Read-only**,
     **Actions: Read-only** (CI status). Metadata: Read-only is added automatically.
3. **Generate token** → copy → `GH_TOKEN` (store per §4).

## 3. claude.ai connectors

1. <https://claude.ai> → **Settings → Connectors**:
   - **Notion** → Connect → in the OAuth screen grant access to the pages the brain
     needs: `CSD EL` and (once it exists, Stage 2) `Second Brain`. Do **not** grant
     `Habit Tracker` or `DND` — they are hard-excluded by design.
   - **Gmail** → Connect with the **personal** Google account.
   - **Google Calendar** → Connect with the **personal** Google account.
2. **Work-account test (setup step zero from the spec):** attempt to connect Gmail /
   Google Calendar with `stanton.borthwick@simplybusiness.co.uk`. If Google shows
   "app blocked", "needs admin approval", or the grant silently fails → the work
   connector is blocked. Apply the fallback:
   - In the **work** Google Calendar → Settings → your calendar → **Share with specific
     people or groups** → add the personal address with **"See all event details"**.
     If org policy only allows free/busy sharing, accept that — busy blocks still shape
     the day.
   - Record in the spec with a dated note: work Google connector blocked; work-email
     triage moves to the roadmap (it is already roadmap item 7).
3. **Local Notion access for Claude Code** (needed in Stages 1–2 to discover page IDs and
   create databases): open a Claude Code session and run `/mcp`. If no Notion tools are
   listed, add the official Notion MCP server locally:
   `claude mcp add --transport http notion https://mcp.notion.com/mcp`
   then authenticate via `/mcp` (OAuth into the same workspace, same page grants).

## 3b. Notion integration token (structured reads)

The connector's query tools are plan-gated (Business + Notion AI), so structured reads
go via a free internal integration (spec note 2026-07-07):

1. <https://www.notion.so/profile/integrations> → **New integration**:
   - Name: `second-brain`. Workspace: yours. Type: **Internal**.
   - Capabilities: **Read content**, **Update content**, **Insert content**. No user
     information needed.
2. Copy the **Internal Integration Secret** → `NOTION_TOKEN` (see §4).
3. Grant it pages (integration tokens see nothing until granted): open **Second Brain**
   → **⋯** menu → **Connections** → add `second-brain`. Repeat for **CSD EL**.
   Do **not** grant Habit Tracker or DnD. (Sub-pages inherit the grant.)
4. CSD EL read-only is a behavioural rule — the token could technically write there;
   the brain never does.

## 4. Local secrets

```sh
mkdir -p ~/.config/second-brain
cat > ~/.config/second-brain/env <<'EOF'
export DISCORD_BOT_TOKEN='...'
export DISCORD_USER_ID='...'
export DISCORD_CAPTURE_CHANNEL_ID='...'
export DISCORD_TEST_CHANNEL_ID='...'
export GH_TOKEN='...'
export NOTION_TOKEN='...'
EOF
chmod 600 ~/.config/second-brain/env
```

Load on demand with `source ~/.config/second-brain/env`. Never commit this file, never
echo these values.

## 5. Validate

```sh
source ~/.config/second-brain/env
./scripts/check-env.sh
```

Every line must be ✅ before Stage 1 starts.

## 6. Cloud environment (configured in Stage 3)

At claude.ai → Claude Code → this repo's cloud environment:
- Network access: **Custom** → default allowlist **plus `discord.com` and `api.notion.com`**.
- Environment variables: the six from §4.
- Connectors enabled for routines: **Notion, Gmail, Google Calendar only** — remove all others.
Exact steps live in the Stage 3 plan.

## 7. Siri voice capture (optional, phone-side only)

1. Discord (desktop): right-click **#capture** → **Edit Channel** → **Integrations** →
   **Webhooks** → **New Webhook** → name `siri-capture` → **Copy Webhook URL**.
   Treat the URL as a secret — anyone holding it can post into #capture.
2. iPhone → **Shortcuts** → **+**, name the shortcut `Capture`:
   - **Ask for Input** (Input Type: Text, prompt: "Capture what?") — invoked via Siri,
     this takes dictation.
   - **Get Contents of URL** → paste the webhook URL → Method **POST** → Request Body
     **JSON** → add field `content` = *Provided Input*.
3. Say "Hey Siri, Capture", dictate, done — the text lands in #capture and the next
   run triages it exactly like a typed message (Message ID dedupe, Capture Log row,
   ✅ reaction). Webhook messages carry a bot-flagged author with its own ID; the
   capture rules ignore only the brain's own bot user ID (CLAUDE.md, 2026-07-10).

## 8. On-demand "brief me now" (iOS Shortcut)

Fires the `morning-briefing` routine ad-hoc from your phone via its **fire endpoint**.
The endpoint is **not shown by default** — a routine ships with only its Scheduled
trigger ("Run now" is the manual control). You reveal it by adding an **API trigger**
(verified on the personal-account Routines UI, Stage 6 Task 1, 2026-07-13). The fire
**token** is a secret — it lives **only** in this Shortcut, never in chat/logs/repo.

1. claude.ai/code/routines → `morning-briefing` → **pencil / Edit routine** →
   **Triggers → Add → API**. Copy the **fire URL** (shape
   `POST https://api.anthropic.com/v1/claude_code/routines/{routine_id}/fire`) and click
   **Generate token** — it's shown **once**, so copy it straight away (Regenerate/Revoke
   from the same modal if it ever leaks). The required header is
   `anthropic-beta: experimental-cc-routine-2026-04-01`.
2. iPhone → **Shortcuts** → **+**, name it `Brief me`:
   - **Ask for Input** (Text, prompt "Focus? (optional)") — dictated via Siri.
   - **Get Contents of URL** → paste the fire URL → Method **POST** →
     **Headers:** `Authorization` = `Bearer <token>`,
     `anthropic-beta` = `experimental-cc-routine-2026-04-01`,
     `Content-Type` = `application/json` →
     Request Body **JSON** → field `text` = *Provided Input*.
3. Say "Hey Siri, Brief me", optionally dictate a focus, done. A DM arrives with the
   briefing; a `morning-<date>-ondemand-<HHMMSS>` Journal page is written; the scheduled
   06:45 run is untouched. Note the quota: **API fires count against the daily routine
   cap** (Pro = 5/day); manual **"Run now"** test fires from the UI don't.

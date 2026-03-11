# OpenClaw + Asana MCP

Connect your [OpenClaw](https://openclaw.ai) agent to [Asana](https://asana.com) via the official Asana MCP server and [mcporter](https://www.npmjs.com/package/mcporter).

Works with **Codex, Claude, or both** — setup detects your model config automatically.

## Prerequisites

- [Node.js](https://nodejs.org) (v18+)
- [OpenClaw](https://openclaw.ai) installed and configured (with Codex, Claude, or both)
- [mcporter](https://www.npmjs.com/package/mcporter) (`npm install -g mcporter`)
- An Asana account with access to your workspace

## Quick Start

```bash
git clone https://github.com/ajdavis21/openclaw-asana-mcp.git
cd openclaw-asana-mcp
chmod +x setup.sh
./setup.sh
```

Setup will ask which mode you want:

### Mode 1: OAuth + Personal PAT backup (recommended)

Best for teams. Each person authorizes their own Asana account via OAuth and saves their individual Personal Access Token as a fallback. OAuth tokens auto-refresh every 50 minutes; the PAT kicks in automatically if a refresh ever fails.

Requires a shared OAuth app (one per team — see below).

### Mode 2: PAT only

Simpler. No OAuth app needed. Each person enters their own Personal Access Token and it's used directly. Good for quick setup or environments where browser-based OAuth isn't practical.

Generate a PAT at: **Asana → My Apps → Personal access tokens**

---

## Team Setup

Each team member runs `./setup.sh` independently on their own machine and enters **their own** Asana PAT. Tokens are stored locally and never shared.

For Mode 1 (OAuth), you'll also need a shared OAuth app:

1. Go to [My Apps](https://app.asana.com/0/my-apps) in Asana
2. Click **Create new app**
3. Add redirect URL: `http://localhost:8931/callback`
4. Share the **Client ID** and **Client Secret** with your team (e.g. in a password manager)

Each person still authenticates their own Asana account — the client ID/secret just identifies the app, not the user.

### Remote Server (SSH)

If running on a remote server, tunnel the callback port before running setup:

```bash
ssh -L 8931:localhost:8931 your-server
./setup.sh
```

To use a different port:

```bash
ASANA_OAUTH_PORT=9999 ./setup.sh
```

### Environment Variables

Skip interactive prompts by setting these before running `setup.sh`:

```bash
export ASANA_CLIENT_ID="your-client-id"
export ASANA_CLIENT_SECRET="your-client-secret"
```

---

## Usage

Once set up, your OpenClaw agent can call Asana tools via the `mcporter` skill:

```bash
# List projects
mcporter call asana.get_projects

# Search tasks
mcporter call asana.search_tasks text="hackathon"

# Create a task
mcporter call asana.create_task name="New task" project_id="<project_gid>"

# Get task details
mcporter call asana.get_task task_id="<task_gid>"

# See all available tools + parameters
mcporter list asana --schema
```

In agent sessions (Codex or Claude), use the `exec` tool:

```
exec mcporter call asana.search_tasks text="Q2 budget"
```

### Available Tools

| Tool | Description |
|------|-------------|
| `get_projects` | List projects in workspace |
| `get_project` | Get project details |
| `create_project` | Create a new project |
| `get_status_overview` | Get project status updates |
| `search_tasks` | Search tasks by text |
| `get_task` | Get task details |
| `create_task` | Create a new task |
| `update_task` | Update an existing task |
| `get_tasks` | List tasks (by project, section, assignee, etc.) |
| `search_objects` | Search across projects, users, tags, goals, etc. |
| `get_user` | Get user details |
| `get_workspace_users` | List workspace members |
| `get_portfolios` | List portfolios |
| `get_portfolio` | Get portfolio details |
| `get_items_for_portfolio` | List projects in a portfolio |

---

## Auth & Token Refresh

| File | Purpose |
|------|---------|
| `~/.openclaw/asana-token.json` | OAuth access + refresh tokens |
| `~/.openclaw/asana-credentials.json` | OAuth client ID/secret (Mode 1 only) |
| `~/.openclaw/asana-pat.txt` | Your personal PAT backup (chmod 600) |
| `~/.mcporter/mcporter.json` | mcporter server config (active Bearer token) |
| `~/.openclaw/asana-refresh.js` | Token refresh script (installed by setup) |
| `~/.openclaw/asana-refresh.log` | Refresh log |

**Refresh logic (Mode 1):**
1. Cron runs `asana-refresh.js` every 50 minutes
2. Attempts OAuth token refresh
3. If refresh fails (expired refresh token, network error, etc.) → falls back to `asana-pat.txt`
4. Applies the active token to `~/.mcporter/mcporter.json`

**PAT-only mode:** cron still runs every 50 min and re-applies the PAT to keep the config current.

---

## Re-authenticating

If your tokens expire or you need to re-authorize:

```bash
./setup.sh
```

---

## Troubleshooting

**"redirect_uri does not match"** — Make sure `http://localhost:8931/callback` is listed as a redirect URL in your Asana app settings.

**Token refresh failing** — Check `~/.openclaw/asana-refresh.log`. If OAuth is broken and no PAT is saved, re-run `./setup.sh`.

**PAT not working** — Verify it at `https://app.asana.com/0/my-apps`. PATs can be revoked; generate a new one and re-run `./setup.sh`.

**mcporter not finding tools** — Run `mcporter list asana --schema` to verify the connection and current Bearer token.

---

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | One-time setup (OAuth or PAT-only, auto-detects model config) |
| `oauth.js` | Browser-based OAuth authorization flow |
| `refresh.js` | Token refresh with PAT fallback (installed to `~/.openclaw/`) |

## License

MIT

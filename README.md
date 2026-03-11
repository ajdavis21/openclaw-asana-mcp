# OpenClaw + Asana MCP

Connect your [OpenClaw](https://openclaw.ai) agent to [Asana](https://asana.com) via the official Asana MCP server and [mcporter](https://www.npmjs.com/package/mcporter).

## Prerequisites

- [Node.js](https://nodejs.org) (v18+)
- [OpenClaw](https://openclaw.ai) installed and configured
- [mcporter](https://www.npmjs.com/package/mcporter) (`npm install -g mcporter`)
- An Asana account with access to your workspace

## Quick Start

### 1. Create an Asana OAuth App

1. Go to [My Apps](https://app.asana.com/0/my-apps) in Asana
2. Click **Create new app**
3. Add a redirect URL: `http://localhost:8931/callback`
4. Note your **Client ID** and **Client Secret**

### 2. Run Setup

```bash
git clone https://github.com/ajdavis21/openclaw-asana-mcp.git
cd openclaw-asana-mcp
chmod +x setup.sh
./setup.sh
```

The setup script will:
- Prompt for your Asana OAuth credentials
- Open a browser-based authorization flow
- Configure mcporter with your Asana MCP connection
- Install a cron job to auto-refresh the token every 50 minutes

### Remote Server (SSH)

If running on a remote server, set up a port forward before running setup:

```bash
ssh -L 8931:localhost:8931 your-server
```

To use a different port:

```bash
ASANA_OAUTH_PORT=9999 ./setup.sh
```

### Environment Variables

You can skip the interactive prompts by setting these before running `setup.sh`:

```bash
export ASANA_CLIENT_ID="your-client-id"
export ASANA_CLIENT_SECRET="your-client-secret"
```

## Usage

Once set up, your OpenClaw agent can use Asana tools via the `mcporter` skill:

```bash
# List projects
mcporter call asana.get_projects

# Search tasks
mcporter call asana.search_tasks text="hackathon"

# Create a task
mcporter call asana.create_task name="New task" project_id="<project_gid>"

# Get task details
mcporter call asana.get_task task_id="<task_gid>"
```

### Available Tools

| Tool | Description |
|------|-------------|
| `get_projects` | List projects in workspace |
| `get_project` | Get project details |
| `create_project` | Create a new project |
| `search_tasks` | Search tasks by text |
| `get_task` | Get task details |
| `create_task` | Create a new task |
| `update_task` | Update an existing task |
| `get_tasks` | List tasks (by project, section, assignee, etc.) |
| `search_objects` | Search across projects, users, tags, goals, etc. |
| `get_user` | Get user details |
| `get_workspace_users` | List workspace members |
| `get_portfolios` | List portfolios |
| `get_status_overview` | Get project status updates |

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | One-time setup script |
| `oauth.js` | Browser-based OAuth authorization flow |
| `refresh.js` | Token refresh (runs via cron) |

### Created during setup

| File | Purpose |
|------|---------|
| `~/.openclaw/asana-token.json` | OAuth tokens (access + refresh) |
| `~/.openclaw/asana-credentials.json` | Client ID/secret for refresh |
| `~/.mcporter/mcporter.json` | mcporter server config |

## Re-Authenticating

If your refresh token expires or you need to re-authorize:

```bash
./setup.sh
```

## Troubleshooting

**"redirect_uri does not match"** — Make sure `http://localhost:8931/callback` is added as a redirect URL in your Asana app settings.

**Token refresh failing** — Check `~/.openclaw/asana-refresh.log`. If the refresh token is invalid, re-run `./setup.sh`.

**mcporter not finding tools** — Run `mcporter list asana --schema` to verify the connection.

## License

MIT

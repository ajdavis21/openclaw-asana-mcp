#!/usr/bin/env bash
set -euo pipefail

# OpenClaw + Asana MCP Setup
# Connects your OpenClaw agent to Asana via mcporter + Asana's official MCP server.

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
MCPORTER_CONFIG="$HOME/.mcporter/mcporter.json"
TOKEN_FILE="$OPENCLAW_DIR/asana-token.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${ASANA_OAUTH_PORT:-8931}"

echo "🦞 OpenClaw + Asana MCP Setup"
echo "=============================="
echo ""

# --- Prerequisites ---
command -v node >/dev/null 2>&1 || { echo "❌ Node.js is required. Install it first."; exit 1; }
command -v mcporter >/dev/null 2>&1 || { echo "❌ mcporter is required. Install via: npm install -g mcporter"; exit 1; }

# --- Asana OAuth App Credentials ---
if [ -z "${ASANA_CLIENT_ID:-}" ] || [ -z "${ASANA_CLIENT_SECRET:-}" ]; then
  echo "You need an Asana OAuth app. Create one at: https://app.asana.com/0/my-apps"
  echo ""
  echo "  1. Click 'Create new app'"
  echo "  2. Add redirect URL: http://localhost:$PORT/callback"
  echo "  3. Copy the Client ID and Client Secret"
  echo ""
  read -rp "Asana Client ID: " ASANA_CLIENT_ID
  read -rp "Asana Client Secret: " ASANA_CLIENT_SECRET
fi

if [ -z "$ASANA_CLIENT_ID" ] || [ -z "$ASANA_CLIENT_SECRET" ]; then
  echo "❌ Client ID and Client Secret are required."
  exit 1
fi

# --- Save credentials for refresh script ---
mkdir -p "$OPENCLAW_DIR"
cat > "$OPENCLAW_DIR/asana-credentials.json" <<EOF
{
  "clientId": "$ASANA_CLIENT_ID",
  "clientSecret": "$ASANA_CLIENT_SECRET"
}
EOF
chmod 600 "$OPENCLAW_DIR/asana-credentials.json"

# --- Run OAuth flow ---
echo ""
echo "Starting OAuth flow on port $PORT..."
echo "If you're on a remote server, set up an SSH tunnel first:"
echo "  ssh -L $PORT:localhost:$PORT <your-server>"
echo ""

ASANA_CLIENT_ID="$ASANA_CLIENT_ID" \
ASANA_CLIENT_SECRET="$ASANA_CLIENT_SECRET" \
ASANA_OAUTH_PORT="$PORT" \
TOKEN_FILE="$TOKEN_FILE" \
node "$SCRIPT_DIR/oauth.js"

if [ ! -f "$TOKEN_FILE" ]; then
  echo "❌ OAuth flow failed — no token file created."
  exit 1
fi

echo ""
echo "✅ Authenticated with Asana!"

# --- Configure mcporter ---
mkdir -p "$(dirname "$MCPORTER_CONFIG")"

ACCESS_TOKEN=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$TOKEN_FILE','utf8')).access_token)")

if [ -f "$MCPORTER_CONFIG" ]; then
  # Update existing config
  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$MCPORTER_CONFIG', 'utf8'));
    cfg.mcpServers = cfg.mcpServers || {};
    cfg.mcpServers.asana = {
      baseUrl: 'https://mcp.asana.com/v2/mcp',
      description: 'Asana project management',
      headers: { Authorization: 'Bearer $ACCESS_TOKEN' }
    };
    fs.writeFileSync('$MCPORTER_CONFIG', JSON.stringify(cfg, null, 2) + '\n');
  "
else
  cat > "$MCPORTER_CONFIG" <<EOF
{
  "mcpServers": {
    "asana": {
      "baseUrl": "https://mcp.asana.com/v2/mcp",
      "description": "Asana project management",
      "headers": {
        "Authorization": "Bearer $ACCESS_TOKEN"
      }
    }
  },
  "imports": []
}
EOF
fi

echo "✅ mcporter configured: $MCPORTER_CONFIG"

# --- Install refresh script ---
cp "$SCRIPT_DIR/refresh.js" "$OPENCLAW_DIR/asana-refresh.js"

# --- Set up cron for auto-refresh ---
CRON_CMD="*/50 * * * * $(which node) $OPENCLAW_DIR/asana-refresh.js >> $OPENCLAW_DIR/asana-refresh.log 2>&1"
(crontab -l 2>/dev/null | grep -v asana-refresh; echo "$CRON_CMD") | crontab -

echo "✅ Auto-refresh cron installed (every 50 min)"

# --- Verify ---
echo ""
echo "Verifying connection..."
if mcporter call asana.get_projects 2>/dev/null | node -e "
  let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
    const p=JSON.parse(d);
    console.log('Found ' + p.length + ' Asana project(s).');
  });
" 2>/dev/null; then
  echo "✅ Asana MCP is working!"
else
  echo "⚠️  Could not verify. Try: mcporter call asana.get_projects"
fi

echo ""
echo "Done! Your OpenClaw agent can now use Asana tools via the mcporter skill."
echo ""
echo "Examples:"
echo "  mcporter call asana.get_projects"
echo "  mcporter call asana.search_tasks text=\"hackathon\""
echo "  mcporter call asana.create_task name=\"New task\" project_id=\"<gid>\""

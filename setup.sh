#!/usr/bin/env bash
set -euo pipefail

# OpenClaw + Asana MCP Setup
# Connects your OpenClaw agent to Asana via mcporter + Asana's official MCP server.
# Works with Codex, Claude, or both — and with OAuth + PAT backup or PAT-only.

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
MCPORTER_CONFIG="$HOME/.mcporter/mcporter.json"
TOKEN_FILE="$OPENCLAW_DIR/asana-token.json"
PAT_FILE="$OPENCLAW_DIR/asana-pat.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${ASANA_OAUTH_PORT:-8931}"

echo "🦞 OpenClaw + Asana MCP Setup"
echo "=============================="
echo ""

# --- Prerequisites ---
command -v node >/dev/null 2>&1 || { echo "❌ Node.js is required. Install it first."; exit 1; }
command -v mcporter >/dev/null 2>&1 || { echo "❌ mcporter is required. Install via: npm install -g mcporter"; exit 1; }

# --- Detect OpenClaw model config ---
OPENCLAW_JSON="$OPENCLAW_DIR/openclaw.json"

if [ -f "$OPENCLAW_JSON" ]; then
  DETECTED=$(node -e "
    const cfg = JSON.parse(require('fs').readFileSync('$OPENCLAW_JSON','utf8'));
    const profiles = cfg.auth?.profiles || {};
    const hasCodex = Object.keys(profiles).some(k => k.startsWith('openai-codex'));
    const hasClaude = Object.keys(profiles).some(k => k.startsWith('anthropic'));
    if (hasCodex && hasClaude) console.log('Codex + Claude (both)');
    else if (hasCodex) console.log('Codex');
    else if (hasClaude) console.log('Claude');
    else console.log('no model auth found');
  " 2>/dev/null || echo "could not read config")

  echo "🤖 Detected model config: $DETECTED"
else
  echo "🤖 OpenClaw config not found — proceeding anyway (mcporter works with any model)"
fi
echo ""

# --- Setup mode ---
echo "Setup mode:"
echo "  1) OAuth + PAT backup  (recommended — automatic token refresh + individual PAT fallback)"
echo "  2) PAT only            (simpler — no shared OAuth app needed)"
echo ""
read -rp "Choose [1/2, default 1]: " MODE_CHOICE
MODE_CHOICE="${MODE_CHOICE:-1}"

mkdir -p "$OPENCLAW_DIR"

if [ "$MODE_CHOICE" = "2" ]; then
  # ---- PAT-only setup ----
  echo ""
  echo "Enter your personal Asana Personal Access Token."
  echo "Generate one at: https://app.asana.com/0/my-apps → Personal access tokens"
  echo ""
  read -rsp "Your Asana PAT: " ASANA_PAT
  echo ""
  if [ -z "$ASANA_PAT" ]; then
    echo "❌ PAT is required."
    exit 1
  fi
  printf '%s' "$ASANA_PAT" > "$PAT_FILE"
  chmod 600 "$PAT_FILE"
  ACCESS_TOKEN="$ASANA_PAT"
  echo "✅ PAT saved."

else
  # ---- OAuth + PAT backup setup ----

  if [ -z "${ASANA_CLIENT_ID:-}" ] || [ -z "${ASANA_CLIENT_SECRET:-}" ]; then
    echo "You need a shared Asana OAuth app (one per team, not per person)."
    echo "Create one at: https://app.asana.com/0/my-apps"
    echo ""
    echo "  1. Click 'Create new app'"
    echo "  2. Add redirect URL: http://localhost:$PORT/callback"
    echo "  3. Copy the Client ID and Client Secret"
    echo ""
    read -rp "Asana Client ID: " ASANA_CLIENT_ID
    read -rsp "Asana Client Secret: " ASANA_CLIENT_SECRET
    echo ""
  fi

  if [ -z "$ASANA_CLIENT_ID" ] || [ -z "$ASANA_CLIENT_SECRET" ]; then
    echo "❌ Client ID and Client Secret are required."
    exit 1
  fi

  cat > "$OPENCLAW_DIR/asana-credentials.json" <<EOF
{
  "clientId": "$ASANA_CLIENT_ID",
  "clientSecret": "$ASANA_CLIENT_SECRET"
}
EOF
  chmod 600 "$OPENCLAW_DIR/asana-credentials.json"

  echo ""
  echo "Starting OAuth flow on port $PORT..."
  echo "If on a remote server, tunnel first:  ssh -L $PORT:localhost:$PORT <your-server>"
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

  # Individual PAT backup
  echo ""
  echo "Personal Access Token backup (your individual PAT — used if OAuth refresh ever fails):"
  echo "Generate one at: https://app.asana.com/0/my-apps → Personal access tokens"
  echo "Press Enter to skip."
  echo ""
  read -rsp "Your Asana PAT (optional but recommended): " ASANA_PAT
  echo ""
  if [ -n "$ASANA_PAT" ]; then
    printf '%s' "$ASANA_PAT" > "$PAT_FILE"
    chmod 600 "$PAT_FILE"
    echo "✅ PAT saved as backup."
  else
    echo "⚠️  No PAT saved. If OAuth refresh fails, re-run setup.sh."
  fi

  ACCESS_TOKEN=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$TOKEN_FILE','utf8')).access_token)")
fi

# --- Configure mcporter ---
mkdir -p "$(dirname "$MCPORTER_CONFIG")"

ACCESS_TOKEN="$ACCESS_TOKEN" node -e "
  const fs = require('fs');
  const configPath = '$MCPORTER_CONFIG';
  const token = process.env.ACCESS_TOKEN;
  let cfg = { mcpServers: {}, imports: [] };
  try { cfg = JSON.parse(fs.readFileSync(configPath, 'utf8')); } catch {}
  cfg.mcpServers = cfg.mcpServers || {};
  cfg.mcpServers.asana = {
    baseUrl: 'https://mcp.asana.com/v2/mcp',
    description: 'Asana project management',
    headers: { Authorization: 'Bearer ' + token }
  };
  fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + '\n', { mode: 0o600 });
"
echo "✅ mcporter configured: $MCPORTER_CONFIG"

# --- Install refresh script ---
cp "$SCRIPT_DIR/refresh.js" "$OPENCLAW_DIR/asana-refresh.js"

# --- Set up cron for auto-refresh ---
NODE_BIN="$(command -v node)"
CRON_CMD="*/50 * * * * $NODE_BIN $OPENCLAW_DIR/asana-refresh.js >> $OPENCLAW_DIR/asana-refresh.log 2>&1"
{ crontab -l 2>/dev/null | grep -v asana-refresh || true; echo "$CRON_CMD"; } | crontab -
echo "✅ Auto-refresh cron installed (every 50 min)"

# --- Verify ---
echo ""
echo "Verifying connection..."
if mcporter call asana.get_projects 2>/dev/null | node -e "
  let d=''; process.stdin.on('data',c=>d+=c); process.stdin.on('end',()=>{
    try { const p=JSON.parse(d); console.log('Found ' + p.length + ' Asana project(s).'); }
    catch(e) { process.exit(1); }
  });
" 2>/dev/null; then
  echo "✅ Asana MCP is working!"
else
  echo "⚠️  Could not verify. Try: mcporter call asana.get_projects"
fi

# --- Summary ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo ""
echo "Files created:"
[ -f "$TOKEN_FILE" ] && echo "  $TOKEN_FILE"
[ -f "$PAT_FILE" ]   && echo "  $PAT_FILE  ← your personal backup PAT"
echo "  $OPENCLAW_DIR/asana-refresh.js"
echo "  $MCPORTER_CONFIG"
echo ""
echo "Your OpenClaw agent can call Asana tools via the mcporter skill:"
echo ""
echo "  mcporter call asana.get_projects"
echo "  mcporter call asana.search_tasks text=\"budget\""
echo "  mcporter call asana.create_task name=\"New task\" project_id=\"<gid>\""
echo ""
echo "In agent sessions:  exec mcporter call asana.<tool> [key=value ...]"
echo "List all tools:     mcporter list asana --schema"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

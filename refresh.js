#!/usr/bin/env node
// Refreshes the Asana OAuth token and updates the mcporter config.
// Falls back to a personal access token (PAT) if OAuth refresh fails.
// Designed to run via cron (every 50 min) to keep the token alive.
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const OPENCLAW_DIR = process.env.OPENCLAW_DIR || path.join(os.homedir(), '.openclaw');
const TOKEN_PATH = path.join(OPENCLAW_DIR, 'asana-token.json');
const CREDS_PATH = path.join(OPENCLAW_DIR, 'asana-credentials.json');
const PAT_PATH = path.join(OPENCLAW_DIR, 'asana-pat.txt');
const MCPORTER_PATH = path.join(os.homedir(), '.mcporter', 'mcporter.json');

const ts = () => new Date().toISOString();

function applyTokenToMcporter(bearerToken) {
  if (!fs.existsSync(MCPORTER_PATH)) {
    console.error(`[${ts()}] WARNING: mcporter config not found at ${MCPORTER_PATH}. Token not applied. Re-run setup.sh.`);
    return;
  }
  const mcporter = JSON.parse(fs.readFileSync(MCPORTER_PATH, 'utf8'));
  if (!mcporter.mcpServers?.asana?.headers) {
    console.error(`[${ts()}] WARNING: No asana entry in mcporter config. Token not applied. Re-run setup.sh.`);
    return;
  }
  mcporter.mcpServers.asana.headers.Authorization = `Bearer ${bearerToken}`;
  fs.writeFileSync(MCPORTER_PATH, JSON.stringify(mcporter, null, 2) + '\n');
}

function fallbackToPAT(reason) {
  console.error(`[${ts()}] OAuth refresh failed: ${reason}`);
  if (!fs.existsSync(PAT_PATH)) {
    console.error(`[${ts()}] No PAT found at ${PAT_PATH}. Re-run setup.sh to configure a backup PAT.`);
    process.exit(1);
  }
  try {
    const pat = fs.readFileSync(PAT_PATH, 'utf8').trim();
    applyTokenToMcporter(pat);
    console.log(`[${ts()}] Asana PAT applied as fallback.`);
  } catch (e) {
    console.error(`[${ts()}] PAT fallback failed:`, e.message);
    process.exit(1);
  }
}

// PAT-only mode: no OAuth credentials on disk
if (!fs.existsSync(CREDS_PATH) || !fs.existsSync(TOKEN_PATH)) {
  if (fs.existsSync(PAT_PATH)) {
    const pat = fs.readFileSync(PAT_PATH, 'utf8').trim();
    applyTokenToMcporter(pat);
    console.log(`[${ts()}] PAT-only mode: Asana PAT applied.`);
    process.exit(0);
  }
  console.error(`[${ts()}] No OAuth credentials or PAT found. Run setup.sh first.`);
  process.exit(1);
}

const tokens = JSON.parse(fs.readFileSync(TOKEN_PATH, 'utf8'));
const creds = JSON.parse(fs.readFileSync(CREDS_PATH, 'utf8'));

const postData = new URLSearchParams({
  grant_type: 'refresh_token',
  client_id: creds.clientId,
  client_secret: creds.clientSecret,
  refresh_token: tokens.refresh_token,
}).toString();

const req = https.request('https://app.asana.com/-/oauth_token', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Content-Length': Buffer.byteLength(postData),
  },
}, (res) => {
  let body = '';
  res.on('data', (d) => (body += d));
  res.on('end', () => {
    try {
      const newTokens = JSON.parse(body);
      if (newTokens.error) {
        fallbackToPAT(JSON.stringify(newTokens));
        return;
      }
      // Preserve refresh_token if not returned in response
      if (!newTokens.refresh_token) newTokens.refresh_token = tokens.refresh_token;

      fs.writeFileSync(TOKEN_PATH, JSON.stringify(newTokens, null, 2), { mode: 0o600 });
      applyTokenToMcporter(newTokens.access_token);
      console.log(`[${ts()}] Asana token refreshed. Expires in ${newTokens.expires_in}s.`);
    } catch (e) {
      fallbackToPAT('Parse error: ' + body);
    }
  });
});
req.on('error', (e) => fallbackToPAT(e.message));
req.write(postData);
req.end();

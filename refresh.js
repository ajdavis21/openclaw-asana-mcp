#!/usr/bin/env node
// Refreshes the Asana OAuth token and updates the mcporter config.
// Designed to run via cron (every 50 min) to keep the token alive.
const https = require('https');
const fs = require('fs');
const path = require('path');
const os = require('os');

const OPENCLAW_DIR = process.env.OPENCLAW_DIR || path.join(os.homedir(), '.openclaw');
const TOKEN_PATH = path.join(OPENCLAW_DIR, 'asana-token.json');
const CREDS_PATH = path.join(OPENCLAW_DIR, 'asana-credentials.json');
const MCPORTER_PATH = path.join(os.homedir(), '.mcporter', 'mcporter.json');

if (!fs.existsSync(TOKEN_PATH)) {
  console.error('No token file found at', TOKEN_PATH);
  process.exit(1);
}
if (!fs.existsSync(CREDS_PATH)) {
  console.error('No credentials file found at', CREDS_PATH);
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
        console.error(`[${new Date().toISOString()}] Refresh failed:`, newTokens);
        process.exit(1);
      }
      // Preserve refresh_token if not returned in response
      if (!newTokens.refresh_token) newTokens.refresh_token = tokens.refresh_token;

      // Save updated tokens
      fs.writeFileSync(TOKEN_PATH, JSON.stringify(newTokens, null, 2));

      // Update mcporter config
      if (fs.existsSync(MCPORTER_PATH)) {
        const mcporter = JSON.parse(fs.readFileSync(MCPORTER_PATH, 'utf8'));
        if (mcporter.mcpServers && mcporter.mcpServers.asana && mcporter.mcpServers.asana.headers) {
          mcporter.mcpServers.asana.headers.Authorization = `Bearer ${newTokens.access_token}`;
          fs.writeFileSync(MCPORTER_PATH, JSON.stringify(mcporter, null, 2) + '\n');
        }
      }

      console.log(`[${new Date().toISOString()}] Asana token refreshed. Expires in ${newTokens.expires_in}s.`);
    } catch (e) {
      console.error(`[${new Date().toISOString()}] Parse error:`, body);
      process.exit(1);
    }
  });
});
req.on('error', (e) => {
  console.error(`[${new Date().toISOString()}] Request error:`, e);
  process.exit(1);
});
req.write(postData);
req.end();

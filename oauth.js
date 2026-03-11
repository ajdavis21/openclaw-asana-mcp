#!/usr/bin/env node
// Asana OAuth2 authorization flow — starts a local callback server,
// exchanges the code for tokens, and saves them to disk.
const http = require('http');
const https = require('https');
const fs = require('fs');
const { execSync } = require('child_process');

const CLIENT_ID = process.env.ASANA_CLIENT_ID;
const CLIENT_SECRET = process.env.ASANA_CLIENT_SECRET;
const PORT = parseInt(process.env.ASANA_OAUTH_PORT || '8931', 10);
const TOKEN_FILE = process.env.TOKEN_FILE || `${process.env.HOME}/.openclaw/asana-token.json`;
const REDIRECT_URI = `http://localhost:${PORT}/callback`;

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error('ASANA_CLIENT_ID and ASANA_CLIENT_SECRET must be set.');
  process.exit(1);
}

const server = http.createServer((req, res) => {
  const parsed = new URL(req.url, `http://localhost:${PORT}`);

  if (parsed.pathname === '/callback' && parsed.searchParams.get('code')) {
    const code = parsed.searchParams.get('code');
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end('<h2>Asana authorized! You can close this tab.</h2>');

    const postData = new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: REDIRECT_URI,
      code,
    }).toString();

    const tokenReq = https.request('https://app.asana.com/-/oauth_token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData),
      },
    }, (tokenRes) => {
      let body = '';
      tokenRes.on('data', (d) => (body += d));
      tokenRes.on('end', () => {
        try {
          const tokens = JSON.parse(body);
          if (tokens.error) {
            console.error('Token exchange failed:', tokens);
            process.exit(1);
          }
          fs.mkdirSync(require('path').dirname(TOKEN_FILE), { recursive: true });
          fs.writeFileSync(TOKEN_FILE, JSON.stringify(tokens, null, 2), { mode: 0o600 });
          console.log('Token saved to', TOKEN_FILE);
          const name = tokens.data?.name || 'Unknown';
          const workspace = tokens.data?.authorized_workspace?.name || 'Unknown';
          console.log(`Authenticated as: ${name} (${workspace})`);
        } catch (e) {
          console.error('Failed to parse token response:', body);
          process.exit(1);
        }
        server.close();
        process.exit(0);
      });
    });
    tokenReq.on('error', (e) => {
      console.error('Token request error:', e);
      process.exit(1);
    });
    tokenReq.write(postData);
    tokenReq.end();
  } else if (parsed.pathname === '/callback' && parsed.searchParams.get('error')) {
    const error = parsed.searchParams.get('error');
    res.writeHead(400, { 'Content-Type': 'text/html' });
    res.end(`<h2>Authorization failed: ${error}</h2>`);
    console.error('OAuth error:', error);
    server.close();
    process.exit(1);
  } else {
    res.writeHead(404);
    res.end('Not found');
  }
});

// Timeout after 5 minutes if no authorization received
const TIMEOUT_MS = 5 * 60 * 1000;
setTimeout(() => {
  console.error('\nTimed out waiting for authorization (5 minutes). Re-run setup.sh to try again.');
  server.close();
  process.exit(1);
}, TIMEOUT_MS);

server.listen(PORT, '127.0.0.1', () => {
  const authUrl = `https://app.asana.com/-/oauth_authorize?client_id=${CLIENT_ID}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&response_type=code`;

  // Try to open browser automatically
  const openCmd = process.platform === 'darwin' ? 'open' : 'xdg-open';
  try {
    execSync(`${openCmd} "${authUrl}"`, { stdio: 'ignore' });
    console.log('\nBrowser opened. Waiting for authorization...');
  } catch {
    console.log(`\nOpen this URL in your browser:\n\n  ${authUrl}\n`);
    console.log(`Waiting for authorization on port ${PORT}...`);
  }
});

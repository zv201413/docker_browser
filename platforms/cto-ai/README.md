# CTO.ai Platform — Browser-in-Container

Run Firefox with Xvfb + noVNC inside a CTO.ai Docker container, accessible via Cloudflare Tunnel.

## Architecture

```
┌───────── CTO.ai Container ──────────────────────┐
│  Firefox → Xvfb :99 (virtual display)           │
│             x11vnc :5900                         │
│             websockify (noVNC) :3000             │
│                  │                              │
│                  └── cloudflared tunnel (token)  │
└─────────────────────────────────────────────────┘
                          │
                          ▼
            https://vnc.your-domain.com/vnc.html
```

## Quick Install

```bash
# One line, with your target URL
TARGET_URL="https://your-site.com" bash -c "$(curl -sSL https://raw.githubusercontent.com/YOUR_USER/docker_browser/main/platforms/cto-ai/install.sh)"
```

### Prerequisites

- CTO.ai container (Ubuntu 22.04) or any Docker-based environment
- Root access via ttyd (you already have this)
- Cloudflare Tunnel running with `--token` (for public access)

### What's installed

| Package | Source | Size |
|---------|--------|------|
| Firefox | Mozilla tar.gz (not snap) | ~280 MB |
| Xvfb | apt | |
| x11vnc | apt | |
| noVNC | apt or GitHub | |
| Supervisor configs | 3 programs | |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TARGET_URL` | `https://client.freemchosting.com/dashboard` | URL to open in Firefox |
| `VNC_PORT` | `3000` | noVNC listen port |
| `DISPLAY_NUM` | `99` | Xvfb display number |

## Supervisor Programs (auto-restart)

```bash
# Status
supervisorctl status browser-xvfb browser-firefox browser-novnc

# Restart Firefox only (keeps VNC up)
supervisorctl restart browser-firefox

# Full restart
supervisorctl restart browser-xvfb browser-firefox browser-novnc
```

## Cloudflare Tunnel Setup

Your cloudflared runs with `--token` (no local config.yml):

1. Go to https://one.dash.cloudflare.com/
2. Find your tunnel → **Public Hostnames** → **Add**
3. Subdomain: `vnc`
4. Service: `HTTP://localhost:3000`
5. Access: `https://vnc.your-domain.com/vnc.html`

## First Use

1. Open `https://vnc.your-domain.com/vnc.html`
2. Click **Connect**
3. Firefox should open your target URL automatically
4. **Solve the Cloudflare challenge** (Firefox passes it, see cf-bypass.md)
5. Log in to your website
6. Profile persisted in `~/.mozilla/firefox/` — survives restarts

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| VNC shows blank | Xvfb lock file | `rm -f /tmp/.X99-lock` + `supervisorctl restart browser-xvfb` |
| 502 from tunnel | noVNC not running | `supervisorctl restart browser-novnc` |
| Firefox not loading | Display not ready | `supervisorctl restart browser-firefox` (retries with sleep) |
| CF challenge fails | Chrome --no-sandbox | You're using Firefox, so this shouldn't happen (see cf-bypass.md) |
| Firefox won't start | Missing libs | `apt install -y libdbus-glib-1-2 libxt6 libxmu6` |

## Files

| File | Purpose |
|------|---------|
| `install.sh` | One-click installer |
| `start-browser.sh` | Browser launcher (env-var driven) |
| `supervisor/browser-xvfb.conf` | Xvfb supervisor config |
| `supervisor/browser-firefox.conf` | Firefox supervisor config |
| `supervisor/browser-novnc.conf` | noVNC supervisor config |
| `cf-bypass.md` | Why Firefox passes CF Turnstile in Docker |

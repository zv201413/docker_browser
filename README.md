# docker_browser — Browser-in-Container

Run a real Firefox browser in any Docker container, with VNC remote access and Cloudflare Turnstile bypass.

## Why Firefox?

Chrome in Docker requires `--no-sandbox`. Cloudflare Turnstile **detects this flag** and rejects manual challenge clicks.

Firefox's sandbox degrades gracefully in containers without producing detectable signals — CF Turnstile works normally. See [cf-bypass.md](platforms/cto-ai/cf-bypass.md).

## One-Click Install (CTO.ai / Docker)

```bash
TARGET_URL="https://client.freemchosting.com/dashboard" bash -c "$(curl -sSL https://raw.githubusercontent.com/zv201413/docker_browser/main/platforms/cto-ai/install.sh)"
```

Or manually:

```bash
git clone https://github.com/zv201413/docker_browser.git
cd docker_browser/platforms/cto-ai
TARGET_URL="https://your-site.com" bash install.sh
```

## What it does

- Installs Firefox 152+ (native tar.gz, bypasses Ubuntu 22.04 snap shim)
- Sets up Xvfb virtual display + x11vnc + noVNC
- Configures supervisor auto-restart (3 independent programs)
- Provides one-time CF Turnstile manual solve via VNC
- Persists Firefox profile across restarts

## Supervised Services

```bash
supervisorctl status browser-xvfb browser-firefox browser-novnc
```

## Cloudflare Tunnel

If using cloudflared `--token` mode:

1. Open https://one.dash.cloudflare.com/
2. Find your tunnel → **Public Hostnames** → **Add**
3. Subdomain: `vnc` → Service: `HTTP://localhost:3000`

## Project Structure

```
docker_browser/
├── platforms/
│   └── cto-ai/              # CTO.ai/Docker deployment
│       ├── install.sh        # One-click installer
│       ├── start-browser.sh  # Browser launcher (env-var driven)
│       ├── supervisor/       # Supervisor configs (3 programs)
│       ├── cf-bypass.md      # CF Turnstile bypass analysis
│       └── README.md         # Detailed docs
└── ANALYSIS.md               # vevc/one-node keepalive analysis
```

## Acknowledgments

This project builds on analysis and inspiration from [vevc/one-node](https://github.com/vevc/one-node) — the original keepalive mechanism that sparked the investigation into browser-in-container behavior and Cloudflare Turnstile bypass.

## License

MIT

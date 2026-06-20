#!/usr/bin/env bash
# ============================================================
# docker_browser — One-click install for CTO.ai / Docker containers
# Usage (as root):
#   curl -sSL https://.../install.sh | bash
#   TARGET_URL="https://example.com" bash install.sh
# ============================================================
set -euo pipefail

TARGET_URL="${TARGET_URL:-https://github.com/zv201413/docker_browser}"
VNC_PORT="${VNC_PORT:-3000}"
INSTALL_DIR="${INSTALL_DIR:-/opt}"

log() { echo -e "\033[1;32m[install]\033[0m $(date '+%H:%M:%S') $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
err()  { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

GH_URL="https://raw.githubusercontent.com/zv201413/docker_browser/main/platforms/cto-ai"

# ----- Check root -----
if [ "$(id -u)" -ne 0 ]; then
  err "Must run as root in the CTO.ai container (ttyd already is root)"
  exit 1
fi

VNC_PASSWORD="${VNC_PASSWORD:-}"
if [ -z "$VNC_PASSWORD" ]; then
  err "VNC_PASSWORD is required — noVNC is exposed via the public Cloudflare tunnel."
  err "Re-run: VNC_PASSWORD='your-strong-pass' TARGET_URL='https://site' bash install.sh"
  exit 1
fi

# ----- Detect supervisor -----
detect_supervisor() {
  for sock in /tmp/supervisor.sock /var/run/supervisor.sock; do
    if [ -S "$sock" ]; then
      echo "$sock"
      return 0
    fi
  done

  for ctl in supervisorctl /usr/local/bin/supervisorctl; do
    if command -v "$ctl" &>/dev/null; then
      local out
      out=$("$ctl" status 2>&1 || true)
      if echo "$out" | grep -q "RUNNING\|EXITED"; then
        log "Found supervisorctl (via PATH)"
        echo "auto"
        return 0
      fi
    fi
  done

  return 1
}

detect_supervisor_confd() {
  for d in /home/zv/boot/system.conf.d /etc/supervisor/conf.d /etc/supervisord.d; do
    if [ -d "$d" ]; then
      echo "$d"
      return 0
    fi
  done

  # If we know supervisor is running but no conf.d, try creating one
  if command -v supervisorctl &>/dev/null; then
    local cfg
    cfg=$(supervisorctl status 2>&1 | head -1)
    if [ -n "$cfg" ]; then
      # Try common locations
      for d in /home/zv/boot/system.conf.d; do
        mkdir -p "$d"
        echo "$d"
        return 0
      done
    fi
  fi

  return 1
}

detect_supervisor_cfg() {
  for conf in /home/zv/boot/supervisord.conf /etc/supervisor/supervisord.conf /etc/supervisord.conf; do
    [ -f "$conf" ] && { echo "$conf"; return 0; }
  done
  return 1
}

SUPERVISOR_SOCK=$(detect_supervisor || true)
SUPERVISOR_CFG=$(detect_supervisor_cfg || true)

# ============================================================
echo ""
log "========================================"
log " docker_browser — Browser-in-Container"
log "========================================"
log "Target URL : ${TARGET_URL}"
log "VNC Port   : ${VNC_PORT}"
log ""

# ----- Step 1: System dependencies -----
log "[1/5] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq xvfb x11vnc wget curl libdbus-glib-1-2 libxt6 libxmu6 \
    libgtk-3-0 libasound2 libx11-xcb1 libpci3 libegl1 libgl1-mesa-glx \
    libxcomposite1 libxrandr2 libxdamage1 libxcursor1 libxinerama1 libxi6 libatk1.0-0 || true

# noVNC: prefer apt, fallback to git
if apt-get install -y -qq novnc 2>/dev/null; then
  log "  noVNC installed via apt"
elif [ ! -f /opt/noVNC/utils/novnc_proxy ]; then
  log "  Installing noVNC from GitHub..."
  apt-get install -y -qq git 2>/dev/null || true
  git clone --depth=1 https://github.com/novnc/noVNC /opt/noVNC 2>/dev/null || {
    warn "git clone failed, trying pip alternative..."
    pip3 install websockify 2>/dev/null || true
  }
fi

# Ensure novnc_proxy is in PATH
if ! command -v novnc_proxy &>/dev/null; then
  NOVNC_PROXY=$(find /usr /opt -name novnc_proxy -type f 2>/dev/null | head -1)
  if [ -n "$NOVNC_PROXY" ]; then
    ln -sf "$NOVNC_PROXY" /usr/local/bin/novnc_proxy
    log "  symlinked novnc_proxy from $NOVNC_PROXY"
  else
    warn "  novnc_proxy not found after install"
  fi
fi

# ----- Step 2: Firefox (native tar, not snap) -----
log "[2/5] Installing Firefox..."
apt-get remove -y firefox chromium-browser 2>/dev/null || true

if command -v firefox &>/dev/null && [ -f /opt/firefox/firefox ] && firefox --version &>/dev/null; then
  log "  Firefox already installed at /opt/firefox"
else
  log "  Downloading Firefox from Mozilla..."
  rm -rf /opt/firefox /usr/local/bin/firefox /tmp/firefox.tar.*
  wget -q --show-progress \
    -O /tmp/firefox.tar.bz2 \
    "https://download.mozilla.org/?product=firefox-latest&os=linux64&lang=zh-CN"

  log "  Extracting..."
  tar xaf /tmp/firefox.tar.bz2 -C /opt/
  ln -sf /opt/firefox/firefox /usr/local/bin/firefox
  rm -f /tmp/firefox.tar.bz2
fi

FIREFOX_VER=$(firefox --version 2>/dev/null || echo "unknown")
log "  Firefox ${FIREFOX_VER}"

# ----- Step 3: Deploy start-browser.sh -----
log "[3/5] Deploying start-browser.sh..."
curl -sSL -o /opt/start-browser.sh "${GH_URL}/start-browser.sh"
chmod +x /opt/start-browser.sh
log "  Installed to /opt/start-browser.sh"
log "  Default URL: ${TARGET_URL} (override via TARGET_URL env var)"

# ----- Step 4: Supervisor config -----
log "[4/5] Installing supervisor configs..."
CONFD=$(detect_supervisor_confd || true)

if [ -n "$CONFD" ]; then
  log "  Supervisor conf.d: ${CONFD}"
  
  # Clean up old broken configs if they exist
  for f in browser-xvfb.conf browser-firefox.conf browser-novnc.conf; do
    if [ -f "$CONFD/$f" ]; then
      rm -f "$CONFD/$f"
      log "  Removed old config: $f"
    fi
  done

  cat > "${CONFD}/browser-launcher.conf" <<EOF
[program:browser-launcher]
command=/opt/start-browser.sh
environment=TARGET_URL="${TARGET_URL}",VNC_PORT="${VNC_PORT}",DISPLAY_NUM="${DISPLAY_NUM:-99}",VNC_PASSWORD="${VNC_PASSWORD}"
autostart=true
autorestart=true
startsecs=5
stopasgroup=true
killasgroup=true
stdout_logfile=/var/log/browser.log
stderr_logfile=/var/log/browser.err
EOF

  SUP_CMD="supervisorctl"
  if [ -n "$SUPERVISOR_CFG" ]; then
    SUP_CMD="supervisorctl -c $SUPERVISOR_CFG"
  elif [ -n "$SUPERVISOR_SOCK" ] && [ "$SUPERVISOR_SOCK" != "auto" ]; then
    SUP_CMD="supervisorctl -s unix://${SUPERVISOR_SOCK}"
  fi

  $SUP_CMD update 2>/dev/null || {
    warn "supervisorctl update failed; trying supervisorctl reload..."
    supervisorctl reload 2>/dev/null || true
  }
else
  warn "No supervisor conf.d directory found."
  warn "Install manually:"
  warn "  mkdir -p /home/zv/boot/system.conf.d"
  warn "  (Create browser-launcher.conf manually)"
  warn "  supervisorctl update"
fi

# ----- Step 5: Start -----
log "[5/5] Starting browser service..."
if [ -n "$CONFD" ]; then
  # Kill any leftover processes from manual runs
  killall Xvfb x11vnc firefox 2>/dev/null || true
  rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

  $SUP_CMD start browser-launcher 2>/dev/null || true

  log "  Status:"
  $SUP_CMD status browser-launcher 2>/dev/null || true
fi

# ----- Done -----
HOSTNAME=$(hostname 2>/dev/null || echo "your-container")
echo ""
log "========================================"
log "  Done!"
log "========================================"
echo ""
echo "  VNC access:  http://${HOSTNAME}:${VNC_PORT}/vnc.html"
echo "  (through CF tunnel: https://vnc.your-domain.com/vnc.html)"
echo ""
echo "  Next steps:"
echo "  1. Open the VNC URL in your browser"
echo "  2. Click Connect → Firefox should open ${TARGET_URL}"
echo "  3. Solve CF challenge manually (one time)"
echo "  4. Log in — profile persists in ~/.mozilla/firefox/"
echo ""
echo "  Management:"
echo "    supervisorctl status browser-launcher"
echo "    supervisorctl restart browser-launcher"
echo ""
echo "  If this is your first time, you also need to:"
echo "  1. Go to https://one.dash.cloudflare.com/"
echo "  2. Find your tunnel → Public Hostnames → Add"
echo "  3. Subdomain: vnc  →  Service: HTTP://localhost:${VNC_PORT}"
echo ""

#!/bin/bash
# Browser launcher for CTO.ai / Docker containers
# Usage: TARGET_URL="https://example.com" ./start-browser.sh
set -euo pipefail

# --- Configuration (overridable via env) ---
DISPLAY_NUM="${DISPLAY_NUM:-99}"
TARGET_URL="${TARGET_URL:-https://example.com}"
VNC_PORT="${VNC_PORT:-3000}"
RESOLUTION="${RESOLUTION:-1280x720x24}"
FIREFOX_PROFILE="${FIREFOX_PROFILE:-/root/.mozilla/firefox}"

export DISPLAY=":${DISPLAY_NUM}"

log() { echo "[browser] $(date '+%H:%M:%S') $*"; }

cleanup() {
  log "Cleaning up old processes..."
  killall Xvfb x11vnc firefox 2>/dev/null || true
  rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
  sleep 0.5
}

ensure_xvfb() {
  Xvfb ":${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" &>/tmp/xvfb.log &
  XVFB_PID=$!
  sleep 1
  if ! kill -0 $XVFB_PID 2>/dev/null; then
    log "ERROR: Xvfb failed to start"
    cat /tmp/xvfb.log
    exit 1
  fi

  for i in $(seq 1 10); do
    if xdpyinfo -display ":${DISPLAY_NUM}" &>/dev/null; then
      log "Xvfb ready (display :${DISPLAY_NUM})"
      return 0
    fi
    sleep 0.5
  done
  log "ERROR: Xvfb did not become ready"
  exit 1
}

# noVNC 启动：websockify 做 WebSocket<->TCP(5900) 转发。
# websockify 包在独立 /opt/websockify，必须 PYTHONPATH 指过去才能 import。
start_novnc() {
  local web="" d ws
  for d in /opt/noVNC /usr/share/novnc /usr/share/noVNC; do
    [ -f "$d/vnc.html" ] && { web="$d"; break; }
  done
  if [ -z "$web" ]; then
    log "ERROR: noVNC static files not found (no vnc.html). Run install.sh first."
    exit 1
  fi
  for ws in /opt/websockify "$web/utils/websockify"; do
    if [ -f "$ws/websockify/__init__.py" ] && [ -f "$ws/run" ]; then
      log "noVNC via websockify ($ws, web=$web)"
      exec env PYTHONPATH="$ws" python3 -m websockify --web "$web" "${VNC_PORT}" localhost:5900
    fi
  done
  log "ERROR: websockify not usable (need <dir>/websockify/__init__.py + run). Re-run install.sh."
  exit 1
}

# --- Main ---

# Security gate: never expose an unauthenticated VNC over the public CF tunnel.
if [ -z "${VNC_PASSWORD:-}" ]; then
  log "ERROR: VNC_PASSWORD not set — refusing to start (would expose an open VNC publicly)."
  log "       Set a password and restart, e.g.:  VNC_PASSWORD='your-strong-pass' bash install.sh"
  exit 1
fi

cleanup
ensure_xvfb

log "Starting Firefox → ${TARGET_URL}"
firefox "${TARGET_URL}" &>/tmp/firefox.log &
FIREFOX_PID=$!
log "Firefox PID: ${FIREFOX_PID}"

sleep 3

log "Starting x11vnc (display :${DISPLAY_NUM})"

echo "$VNC_PASSWORD" > /tmp/vnc.passwd
chmod 600 /tmp/vnc.passwd
x11vnc -display ":${DISPLAY_NUM}" -forever -passwdfile /tmp/vnc.passwd -quiet &>/tmp/x11vnc.log &
X11VNC_PID=$!
sleep 1
rm -f /tmp/vnc.passwd

log "Starting noVNC proxy (port ${VNC_PORT})"
start_novnc

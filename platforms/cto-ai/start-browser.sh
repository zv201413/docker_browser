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
  if ! Xvfb ":${DISPLAY_NUM}" -screen 0 "${RESOLUTION}" &>/tmp/xvfb.log; then
    log "ERROR: Xvfb failed to start"
    cat /tmp/xvfb.log
    exit 1
  fi
  XVFB_PID=$!

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

ensure_novnc() {
  NOVNC_DIR=""
  for d in /opt/noVNC /usr/share/novnc /usr/share/noVNC; do
    if [ -f "$d/utils/novnc_proxy" ]; then
      NOVNC_DIR="$d"
      break
    fi
  done

  if [ -z "$NOVNC_DIR" ]; then
    log "ERROR: noVNC not found. Run install.sh first."
    exit 1
  fi
  echo "$NOVNC_DIR"
}

# --- Main ---
cleanup
ensure_xvfb

log "Starting Firefox → ${TARGET_URL}"
firefox "${TARGET_URL}" &>/tmp/firefox.log &
FIREFOX_PID=$!
log "Firefox PID: ${FIREFOX_PID}"

sleep 3

log "Starting x11vnc (display :${DISPLAY_NUM})"
x11vnc -display ":${DISPLAY_NUM}" -forever -nopw -quiet &>/tmp/x11vnc.log &
X11VNC_PID=$!

log "Starting noVNC proxy (port ${VNC_PORT})"
NOVNC_DIR="$(ensure_novnc)"
exec "${NOVNC_DIR}/utils/novnc_proxy" \
  --vnc localhost:5900 \
  --listen "${VNC_PORT}"

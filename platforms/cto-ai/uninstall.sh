#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\033[1;31m[uninstall]\033[0m $(date '+%H:%M:%S') $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

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
        echo "auto"
        return 0
      fi
    fi
  done
  return 1
}

# ----- Detect supervisor conf.d -----
detect_confd() {
  for d in /home/zv/boot/system.conf.d /etc/supervisor/conf.d /etc/supervisord.d; do
    if [ -d "$d" ]; then
      echo "$d"
      return 0
    fi
  done
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
SUP_CMD="supervisorctl"
if [ -n "$SUPERVISOR_CFG" ]; then
  SUP_CMD="supervisorctl -c $SUPERVISOR_CFG"
elif [ -n "$SUPERVISOR_SOCK" ] && [ "$SUPERVISOR_SOCK" != "auto" ]; then
  SUP_CMD="supervisorctl -s unix://${SUPERVISOR_SOCK}"
fi

# ----- Stop supervisor programs -----
log "[1/4] Stopping browser services..."
for prog in browser-launcher browser-xvfb browser-firefox browser-novnc browser-health; do
  $SUP_CMD stop "$prog" 2>/dev/null && log "  stopped $prog" || true
done

# ----- Remove supervisor configs -----
log "[2/4] Removing supervisor configs..."
CONFD=$(detect_confd || true)
if [ -n "$CONFD" ]; then
  for f in browser-launcher.conf browser-xvfb.conf browser-firefox.conf browser-novnc.conf browser-health.conf; do
    rm -f "$CONFD/$f" && log "  removed $CONFD/$f" || true
  done
  $SUP_CMD update 2>/dev/null || true
else
  warn "  supervisor conf.d not found, skipping"
fi

# ----- Kill leftover processes -----
log "[3/4] Killing leftover processes..."
killall Xvfb 2>/dev/null && log "  killed Xvfb" || true
killall x11vnc 2>/dev/null && log "  killed x11vnc" || true
killall firefox 2>/dev/null && log "  killed firefox" || true
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

# ----- Remove installed files -----
log "[4/4] Removing installed files..."
rm -f /opt/start-browser.sh
rm -f /opt/health-check.sh /root/health-check.sh
rm -rf /opt/firefox
rm -f /usr/local/bin/firefox

echo ""
log "========================================"
log "  Uninstall complete!"
log "========================================"
echo ""
echo "  To also remove shared packages:"
echo "    apt-get remove --purge xvfb x11vnc novnc"
echo "    apt-get autoremove"
echo ""

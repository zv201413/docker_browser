#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\033[1;31m[uninstall]\033[0m $(date '+%H:%M:%S') $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m  $*"; }

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

# ----- Stop supervisor programs -----
log "[1/4] Stopping browser services..."
for prog in browser-xvfb browser-firefox browser-novnc browser-health; do
  supervisorctl stop "$prog" 2>/dev/null && log "  stopped $prog" || true
done

# ----- Remove supervisor configs -----
log "[2/4] Removing supervisor configs..."
CONFD=$(detect_confd || true)
if [ -n "$CONFD" ]; then
  for f in browser-xvfb.conf browser-firefox.conf browser-novnc.conf browser-health.conf; do
    rm -f "$CONFD/$f" && log "  removed $CONFD/$f" || true
  done
  supervisorctl update 2>/dev/null || supervisorctl reload 2>/dev/null || true
else
  warn "  supervisor conf.d not found, skipping"
fi

# ----- Kill leftover processes -----
log "[3/4] Killing leftover processes..."
killall Xvfb x11vnc firefox 2>/dev/null && log "  processes killed" || true
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

# ----- Remove installed files -----
log "[4/4] Removing installed files..."
rm -f /opt/start-browser.sh
rm -f /opt/health-check.sh
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

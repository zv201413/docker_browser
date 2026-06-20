#!/bin/bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-https://example.com}"
VNC_PORT="${VNC_PORT:-3000}"
FIREFOX_PROFILE="${FIREFOX_PROFILE:-/root/.mozilla/firefox}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
CURL_TIMEOUT=15

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

check_firefox_process() {
  if ! pgrep -f firefox > /dev/null 2>&1; then
    log "FAIL firefox process"
    return 1
  fi
  log "OK firefox process"
  return 0
}

check_vnc_port() {
  if ! timeout 5 bash -c "echo > /dev/tcp/localhost/$VNC_PORT" 2>/dev/null; then
    log "FAIL vnc port $VNC_PORT"
    return 1
  fi
  log "OK vnc port $VNC_PORT"
  return 0
}

check_cookie_validity() {
  if [ ! -d "$FIREFOX_PROFILE" ]; then
    log "SKIP cookie (no profile dir)"
    return 0
  fi
  local last_mtime
  last_mtime=$(find "$FIREFOX_PROFILE" -name "cookies.sqlite" -exec stat -c %Y {} \; 2>/dev/null | sort -rn | head -1)
  if [ -z "$last_mtime" ]; then
    log "SKIP cookie (no cookies.sqlite)"
    return 0
  fi
  local age=$(( $(date +%s) - last_mtime ))
  if [ "$age" -lt 7200 ]; then
    log "OK cookie age $((age / 60))min"
    return 0
  else
    log "WARN cookie age $((age / 3600))h (stale)"
    return 1
  fi
}

check_page_reachability() {
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 5 --max-time "$CURL_TIMEOUT" \
    -A "Mozilla/5.0 (X11; Linux x86_64; rv:127.0) Gecko/20100101 Firefox/127.0" \
    "$TARGET_URL" 2>/dev/null || echo "000")

  case "$http_code" in
    200|301|302|303|307|308) log "OK http $http_code" ; return 0 ;;
    403|429)                  log "WARN http $http_code (cf challenge/ratelimit)" ; return 1 ;;
    000)                      log "FAIL http timeout/dns/refused" ; return 1 ;;
    *)                        log "FAIL http $http_code" ; return 1 ;;
  esac
}

send_alert() {
  local msg="$1"
  local severity="${2:-warn}"
  if [ -z "$ALERT_WEBHOOK" ]; then
    log "[alert] $severity: $msg"
    return
  fi
  local payload
  payload=$(cat <<EOF
{
  "text": "[docker_browser] [$severity] $msg",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
  curl -s -X POST "$ALERT_WEBHOOK" -H "Content-Type: application/json" -d "$payload" > /dev/null 2>&1 || log "WARN alert send failed"
}

main() {
  local healthy=0 failed=0

  for check in check_firefox_process check_vnc_port check_cookie_validity check_page_reachability; do
    if eval "$check"; then
      ((healthy++))
    else
      ((failed++))
    fi
  done

  if [ "$failed" -eq 0 ]; then
    log "RESULT $healthy/4 pass"
    return 0
  fi

  if [ "$failed" -ge 3 ]; then
    send_alert "Browser CRITICAL: $healthy/4 pass" "critical"
  elif [ "$failed" -ge 2 ]; then
    send_alert "Browser WARN: $healthy/4 pass" "warn"
  fi

  log "RESULT $healthy/4 pass $failed/4 fail"
  return "$failed"
}

main "$@"

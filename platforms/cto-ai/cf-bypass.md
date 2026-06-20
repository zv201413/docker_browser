# Cloudflare Turnstile Bypass: Why Firefox works and Chrome doesn't

> Real-world finding: CTO.ai Docker container (Ubuntu 22.04), Firefox 152.0.1, June 2026.

## The Problem

Running a browser in Docker to access Cloudflare-protected websites:

```
Chrome + Xvfb + noVNC
  → CF Turnstile challenge loads visually
  → User manually clicks "I am human"
  → CF rejects the token → page stuck forever
```

Chrome **must** run with `--no-sandbox` in Docker (no user namespaces). Cloudflare Turnstile detects this and silently rejects the challenge response, even from a real human click.

## Root Cause

| Factor | Chrome | Firefox |
|--------|--------|---------|
| Sandbox in Docker | `--no-sandbox` required | Graceful degradation |
| Detectable flag | ✅ Yes — `--no-sandbox` is visible | ❌ No equivalent |
| Turnstile behavior | Renders challenge, click rejected | Challenge accepted normally |
| GPU/WebGL | Missing in Xvfb | Same (both use software render) |

The sandbox status is the **only meaningful difference**. Both browsers lack GPU, both run in Xvfb, both have dbus warnings. But Chrome's `--no-sandbox` is a hard signal that Turnstile acts on.

## Test Results (CTO.ai container, Ubuntu 22.04)

| Browser | Config | Challenge | Manual Click | Result |
|---------|--------|-----------|-------------|--------|
| Chrome 149 | `--no-sandbox --disable-gpu` | ✅ Renders | ❌ Rejected | ❌ |
| Firefox 152 | No special flags | ✅ Renders | ✅ Accepted | ✅ |

## Why Firefox doesn't need `--no-sandbox`

Firefox in Docker logs `CanCreateUserNamespace() clone() failure: EPERM` but continues with reduced isolation using:

- Content process sandboxing (works without CLONE_NEWUSER)
- `LD_PRELOAD`-based sandbox as fallback
- No user-facing `--no-sandbox` flag that JavaScript can detect

Turnstile checks for `--no-sandbox` via `navigator.webdriver`, process argument inspection, and sandbox API probing. Firefox's fallback path doesn't trigger these detectors.

## First-Time Setup

1. Open `https://vnc.your-domain.com/vnc.html` in your local browser
2. Click **Connect** → Firefox desktop appears
3. Navigate to the CF-protected site
4. **Manually solve the Turnstile/CAPTCHA** (one time)
5. Log in — cookies are saved to `~/.mozilla/firefox/`

## Limitations

- **Not automated bypass**: Requires human interaction for first login and after cookie expiry
- **IP reputation**: If CF hard-blocks your IP (not just challenges), no browser helps. Check with `curl -sI https://target.site | grep cf-mitigated`:
  - `cf-mitigated: challenge` → Firefox works
  - `cf-mitigated: blocked` or no header → IP-level block
- **Cookie expiry**: Session cookies eventually expire. Re-open VNC and re-login.

## Verification

```bash
# Check if the browser has --no-sandbox (should be 0 for Firefox)
ps aux | grep -c no-sandbox

# Check CF response type
curl -sI https://your-target-site.com | grep cf-mitigated

# Verify Firefox is running with proper display
ps aux | grep firefox | head -3
```

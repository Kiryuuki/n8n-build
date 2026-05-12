#!/bin/sh
set -e

# ── Sanity check ──────────────────────────────────────────────────────────────
if [ ! -f /usr/bin/chromium-browser ]; then
    echo "[ENTRYPOINT] ERROR: chromium-browser not found at /usr/bin/chromium-browser"
    exit 1
fi

# ── Start Chromium in headless mode with CDP ──────────────────────────────────
# --headless=new: true headless, no display server needed (no Xvfb)
# --no-sandbox: required inside Docker/LXC (no kernel namespace support)
# --disable-dev-shm-usage: use /tmp instead of /dev/shm (avoids 64MB default limit)
chromium-browser \
    --remote-debugging-port=9222 \
    --remote-debugging-address=0.0.0.0 \
    --no-sandbox \
    --disable-dev-shm-usage \
    --disable-gpu \
    --headless=new \
    --user-data-dir=/tmp/chrome-data \
    --disable-extensions \
    --disable-background-networking \
    --disable-default-apps \
    --mute-audio \
    &

CHROME_PID=$!
sleep 1

# ── Verify Chromium started ───────────────────────────────────────────────────
if ! kill -0 $CHROME_PID 2>/dev/null; then
    echo "[ENTRYPOINT] WARNING: Chromium failed to start, n8n will still run"
    echo "[ENTRYPOINT] CDP unavailable — check chromium-browser binary"
else
    echo "[ENTRYPOINT] Chromium CDP on :9222 (PID $CHROME_PID)"
fi

echo "[ENTRYPOINT] Starting n8n..."

# ── Drop to node user and start n8n ──────────────────────────────────────────
exec su-exec node n8n start
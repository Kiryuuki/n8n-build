#!/bin/sh
set -e

# Verify chromium binary exists
if [ ! -f /usr/bin/chromium-browser ]; then
    echo "[ENTRYPOINT] ERROR: chromium-browser not found"
    exit 1
fi

# Start Chromium headless with CDP — no Xvfb needed
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

if ! kill -0 $CHROME_PID 2>/dev/null; then
    echo "[ENTRYPOINT] WARNING: Chromium failed to start — CDP unavailable"
else
    echo "[ENTRYPOINT] Chromium CDP on :9222 (PID $CHROME_PID)"
fi

echo "[ENTRYPOINT] Starting n8n..."
exec su-exec node n8n start
#!/bin/sh
set -e

# Verify chromium binary exists before attempting to start
if [ ! -f /usr/bin/chromium-browser ]; then
    echo "[ENTRYPOINT] ERROR: /usr/bin/chromium-browser not found"
    exit 1
fi

# Start Chromium in true headless mode with CDP.
# --headless=new does not need Xvfb.
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

echo "[ENTRYPOINT] Chromium CDP on :9222 (PID $CHROME_PID)"
echo "[ENTRYPOINT] Starting n8n..."

exec su-exec node n8n start
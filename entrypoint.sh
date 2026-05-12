#!/bin/sh
set -e

# Start Chromium with CDP enabled in true headless mode.
# No Xvfb needed — headless Chromium renders without a display server.
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

# Brief wait for CDP socket to open before n8n workflows try to connect
sleep 1

echo "[ENTRYPOINT] Chromium CDP listening on :9222 (PID $CHROME_PID)"
echo "[ENTRYPOINT] Starting n8n..."

# Hand off to n8n as the node user.
# n8nio/base image provides tini as PID 1 via its own entrypoint chain,
# but since we override ENTRYPOINT we exec n8n directly here.
exec su-exec node n8n start
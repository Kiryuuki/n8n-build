#!/bin/sh
set -e

# 1. Start Xvfb virtual display
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
sleep 2

# 2. Start Chromium with CDP in background
chromium-browser \
  --remote-debugging-port=9222 \
  --remote-debugging-address=0.0.0.0 \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --headless \
  --user-data-dir=/tmp/chrome-data \
  &

sleep 1
echo "[ENTRYPOINT] Xvfb PID: $XVFB_PID"
echo "[ENTRYPOINT] Chrome CDP listening on :9222"
echo "[ENTRYPOINT] Starting n8n as node user..."

# 3. Hand off to n8n as node user
exec su-exec node n8n start

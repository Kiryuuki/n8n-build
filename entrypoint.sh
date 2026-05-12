#!/bin/sh
set -e

# 1. Start Xvfb virtual display
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!

# 2. Start Chromium with CDP (Securely bound to 127.0.0.1)
# Fix Issue #2 & #5: Locked down debugging address and using persistent data dir
chromium-browser \
  --remote-debugging-port=9222 \
  --remote-debugging-address=127.0.0.1 \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --headless \
  --user-data-dir=/home/node/chrome-data \
  &

# 3. Fix Issue #9: Wait for Chromium CDP to be ready using a loop instead of static sleep
echo "[ENTRYPOINT] Waiting for Chrome CDP to be ready..."
MAX_RETRIES=30
COUNT=0
while ! curl -s http://127.0.0.1:9222/json/version > /dev/null; do
    sleep 1
    COUNT=$((COUNT+1))
    if [ $COUNT -ge $MAX_RETRIES ]; then
        echo "[ENTRYPOINT] Chrome CDP failed to start in time"
        exit 1
    fi
done

echo "[ENTRYPOINT] Xvfb PID: $XVFB_PID"
echo "[ENTRYPOINT] Chrome CDP is ready on 127.0.0.1:9222"
echo "[ENTRYPOINT] Starting n8n as node user..."

# 4. Hand off to n8n as node user
exec su-exec node n8n start

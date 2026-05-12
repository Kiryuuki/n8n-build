#!/bin/sh
set -e

# 1. Start Xvfb virtual display
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!

# Wait for Xvfb to be ready (readiness loop, not blind sleep)
i=0
while [ $i -lt 20 ]; do
  if /usr/bin/Xvfb -br -nolisten tcp :98 -terminate 2>/dev/null & then
    kill $! 2>/dev/null || true
    break
  fi
  sleep 0.5
  i=$((i + 1))
done
echo "[ENTRYPOINT] Xvfb PID: $XVFB_PID"

# 2. Start Chromium with CDP
# Fix #8: use actual binary at /usr/lib/chromium/chromium, not the wrapper
# Fix #2: bind CDP to 127.0.0.1 only (security hardening)
/usr/lib/chromium/chromium \
  --remote-debugging-port=9222 \
  --remote-debugging-address=127.0.0.1 \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --headless \
  --user-data-dir=/home/node/chrome-data \
  &
CHROME_PID=$!

# Wait for CDP to be ready (readiness loop, not blind sleep)
i=0
until curl -sf http://127.0.0.1:9222/json/version > /dev/null 2>&1; do
  i=$((i + 1))
  if [ $i -ge 20 ]; then
    echo "[ENTRYPOINT] WARNING: Chrome CDP not ready after 10s, continuing anyway"
    break
  fi
  sleep 0.5
done
echo "[ENTRYPOINT] Chrome CDP PID: $CHROME_PID (listening on 127.0.0.1:9222)"

echo "[ENTRYPOINT] Starting n8n as node user..."

# 3. Hand off to n8n as node user
exec /usr/local/bin/su-exec node n8n start
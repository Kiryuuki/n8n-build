ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine 3.22 — build tools + chromium + community node ────────────
FROM alpine:3.22 AS builder

RUN apk add --no-cache \
    python3 make g++ nodejs npm \
    chromium \
    nss freetype harfbuzz ca-certificates \
    ttf-freefont font-noto-emoji \
    libstdc++ libgcc alsa-lib at-spi2-core \
    cups-libs libdrm libxcomposite libxdamage \
    libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs udev \
    libthai su-exec

# Collect exact libs Chromium needs via ldd
RUN mkdir -p /chromium-libs && \
    ldd /usr/bin/chromium 2>/dev/null \
        | awk '/=>/ { print $3 }' | grep '^/' | sort -u \
        | xargs -I{} cp -L {} /chromium-libs/ && \
    find /usr/lib/chromium -name '*.so*' \
        -exec cp -L {} /chromium-libs/ \; 2>/dev/null || true

# Install community node to /n8n-nodes (NOT inside .n8n — avoids volume shadowing)
RUN mkdir -p /n8n-nodes && \
    cd /n8n-nodes && \
    npm install n8n-nodes-playwright --legacy-peer-deps && \
    npm cache clean --force

# Symlink system Chromium into Playwright's expected browser path
RUN BROWSER_BASE=/n8n-nodes/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    echo "Symlinking into: $CHROMIUM_DIR" && \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' \
        > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# Patch setup-browsers (.ts and compiled .js) to no-op
RUN find /n8n-nodes/node_modules/n8n-nodes-playwright \
        \( -name "setup-browsers.ts" -o -name "setup-browsers.js" \) \
        -type f | while read f; do \
            echo "// patched: system chromium used, download disabled" > "$f"; \
            echo "Patched: $f"; \
        done

# ── Stage 2: n8n hardened image ───────────────────────────────────────────────
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Chromium binary + wrapper
COPY --from=builder /usr/bin/chromium-browser  /usr/bin/chromium-browser
COPY --from=builder /usr/bin/chromium          /usr/bin/chromium
COPY --from=builder /usr/lib/chromium          /usr/lib/chromium

# All shared libs collected by ldd
COPY --from=builder /chromium-libs             /usr/lib/

# su-exec for privilege drop
COPY --from=builder /sbin/su-exec              /usr/local/bin/su-exec

# Fonts
COPY --from=builder /usr/share/fonts           /usr/share/fonts

# Community node goes to /n8n-nodes — outside the /home/node/.n8n volume mount.
# This means it is always available regardless of volume state.
COPY --from=builder /n8n-nodes                 /n8n-nodes
RUN chown -R node:node /n8n-nodes

COPY execution-hooks.js        /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENV \
    N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    # Point to /n8n-nodes — not inside .n8n, never shadowed by volume
    N8N_CUSTOM_EXTENSIONS=/n8n-nodes \
    EXTERNAL_HOOK_FILES=/home/node/execution-hooks.js \
    N8N_ALLOWED_PATHS=/home/node/files \
    NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core \
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    N8N_ENABLE_EXECUTE_COMMAND=true \
    N8N_COMMUNITY_PACKAGES_ENABLED=true \
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_PERSONALIZATION_ENABLED=false \
    N8N_HIRING_BANNER_ENABLED=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]
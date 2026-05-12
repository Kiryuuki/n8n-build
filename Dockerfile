ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine 3.22 ───────────────────────────────────────────────────────
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
    libthai \
    su-exec

# Collect exact libs Chromium needs via ldd
RUN mkdir -p /chromium-libs && \
    ldd /usr/bin/chromium 2>/dev/null \
        | awk '/=>/ { print $3 }' \
        | grep '^/' \
        | sort -u \
        | xargs -I{} cp -L {} /chromium-libs/ && \
    find /usr/lib/chromium -name '*.so*' \
        -exec cp -L {} /chromium-libs/ \; 2>/dev/null || true

# Install into /home/node/.n8n/nodes — this is where n8n community nodes live
# when installed via UI. We pre-populate it so the volume gets it on first start.
RUN mkdir -p /home/node/.n8n/nodes && \
    cd /home/node/.n8n/nodes && \
    npm install n8n-nodes-playwright --legacy-peer-deps && \
    npm cache clean --force

# Verify the actual chromium dir name after install
RUN BROWSER_BASE=/home/node/.n8n/nodes/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    echo "Browser base contents:" && ls ${BROWSER_BASE} 2>/dev/null || echo "dir not found"

# Symlink system Chromium — target the actual versioned dir found after install
RUN BROWSER_BASE=/home/node/.n8n/nodes/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    echo "Using chromium dir: $CHROMIUM_DIR" && \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    # Stub webkit + firefox
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' \
        > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# Patch setup-browsers in both possible paths
RUN find /home/node/.n8n/nodes/node_modules/n8n-nodes-playwright \
        \( -name "setup-browsers.ts" -o -name "setup-browsers.js" \) \
        -type f | while read f; do \
            echo "// patched: system chromium used, download disabled" > "$f"; \
            echo "Patched: $f"; \
        done

# ── Stage 2: n8n hardened image ───────────────────────────────────────────────
FROM n8nio/n8n:${N8N_VERSION}

USER root

COPY --from=builder /usr/bin/chromium-browser  /usr/bin/chromium-browser
COPY --from=builder /usr/bin/chromium          /usr/bin/chromium
COPY --from=builder /usr/lib/chromium          /usr/lib/chromium
COPY --from=builder /chromium-libs             /usr/lib/
COPY --from=builder /sbin/su-exec              /usr/local/bin/su-exec
COPY --from=builder /usr/share/fonts           /usr/share/fonts

# Copy into /home/node/.n8n/nodes (matches n8n's community node install path)
COPY --from=builder /home/node/.n8n/nodes      /home/node/.n8n/nodes

RUN chown -R node:node /home/node/.n8n

COPY execution-hooks.js        /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENV \
    N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    # Point to nodes dir not custom dir
    N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/nodes \
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
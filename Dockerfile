ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine — install Chromium and system deps ────────────────────────
FROM alpine:3.22 AS browser-installer

RUN apk add --no-cache \
    chromium \
    chromium-chromedriver \
    xvfb \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    font-noto-emoji \
    udev \
    libstdc++ \
    alsa-lib \
    at-spi2-core \
    cups-libs \
    libdrm \
    libxcomposite \
    libxdamage \
    libxfixes \
    libxkbcommon \
    libxrandr \
    mesa-gbm \
    pango \
    cairo \
    glib \
    gtk+3.0 \
    dbus \
    dbus-libs \
    su-exec

# ── Stage 2: n8n hardened image — copy Chromium from Alpine ───────────────────
FROM n8nio/n8n:${N8N_VERSION}
USER root

# Copy Chromium binaries
COPY --from=browser-installer /usr/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=browser-installer /usr/bin/chromium-chromedriver /usr/bin/chromium-chromedriver
COPY --from=browser-installer /usr/lib/chromium /usr/lib/chromium

# Copy Xvfb and su-exec
COPY --from=browser-installer /usr/bin/Xvfb /usr/bin/Xvfb
COPY --from=browser-installer /usr/bin/su-exec /usr/bin/su-exec

# Copy all shared libs needed by Chromium (usr/lib)
COPY --from=browser-installer /usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6
COPY --from=browser-installer /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1
COPY --from=browser-installer /usr/lib/libdbus-1.so.3 /usr/lib/libdbus-1.so.3
COPY --from=browser-installer /usr/lib/libnss3.so /usr/lib/libnss3.so
COPY --from=browser-installer /usr/lib/libnssutil3.so /usr/lib/libnssutil3.so
COPY --from=browser-installer /usr/lib/libsmime3.so /usr/lib/libsmime3.so
COPY --from=browser-installer /usr/lib/libssl3.so /usr/lib/libssl3.so
COPY --from=browser-installer /usr/lib/libplds4.so /usr/lib/libplds4.so
COPY --from=browser-installer /usr/lib/libplc4.so /usr/lib/libplc4.so
COPY --from=browser-installer /usr/lib/libnspr4.so /usr/lib/libnspr4.so
COPY --from=browser-installer /usr/lib/libfreetype.so.6 /usr/lib/libfreetype.so.6
COPY --from=browser-installer /usr/lib/libharfbuzz.so.0 /usr/lib/libharfbuzz.so.0
COPY --from=browser-installer /usr/lib/libasound.so.2 /usr/lib/libasound.so.2
COPY --from=browser-installer /usr/lib/libglib-2.0.so.0 /usr/lib/libglib-2.0.so.0
COPY --from=browser-installer /usr/lib/libgobject-2.0.so.0 /usr/lib/libgobject-2.0.so.0
COPY --from=browser-installer /usr/lib/libgio-2.0.so.0 /usr/lib/libgio-2.0.so.0
COPY --from=browser-installer /usr/lib/libpango-1.0.so.0 /usr/lib/libpango-1.0.so.0
COPY --from=browser-installer /usr/lib/libcairo.so.2 /usr/lib/libcairo.so.2
COPY --from=browser-installer /usr/lib/libgbm.so.1 /usr/lib/libgbm.so.1
COPY --from=browser-installer /usr/lib/libxkbcommon.so.0 /usr/lib/libxkbcommon.so.0
COPY --from=browser-installer /usr/lib/libatspi.so.0 /usr/lib/libatspi.so.0
COPY --from=browser-installer /usr/lib/libcups.so.2 /usr/lib/libcups.so.2
COPY --from=browser-installer /usr/lib/libdrm.so.2 /usr/lib/libdrm.so.2

# Pre-install community node at build time
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Symlink system Chromium for Playwright binary check
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    if [ -z "$CHROMIUM_DIR" ]; then \
        CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148"; \
    fi && \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    echo "#!/bin/sh" > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p ${BROWSER_BASE}/firefox-1511/linux && \
    touch ${BROWSER_BASE}/firefox-1511/linux/firefox && \
    chmod +x ${BROWSER_BASE}/firefox-1511/linux/firefox && \
    chown -R node:node /home/node/.n8n

# Copy hooks and entrypoint
COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Environment variables
ENV N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    N8N_ENABLE_EXECUTE_COMMAND=true \
    NODES_EXCLUDE=[] \
    EXTERNAL_HOOK_FILES=/home/node/execution-hooks.js \
    N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom \
    N8N_ALLOWED_PATHS=/home/node/files \
    NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core \
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    N8N_COMMUNITY_PACKAGES_ENABLED=true \
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_PERSONALIZATION_ENABLED=false \
    N8N_HIRING_BANNER_ENABLED=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    DISPLAY=:99

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]

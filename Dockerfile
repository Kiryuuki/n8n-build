ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine — install Chromium + Xvfb + build community node ──────────
FROM alpine:3.22 AS browser-installer

RUN apk add --no-cache \
    python3 make g++ nodejs npm \
    chromium \
    xvfb \
    mesa-gl \
    nss freetype harfbuzz \
    ca-certificates ttf-freefont font-noto-emoji \
    udev libstdc++ alsa-lib at-spi2-core cups-libs libdrm \
    libxcomposite libxdamage libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs \
    su-exec curl

# Confirm actual Chromium binary paths (Alpine uses wrapper + real binary)
RUN echo "=== Chromium paths ===" && \
    ls -la /usr/bin/chromium* 2>/dev/null || true && \
    ls -la /usr/lib/chromium/ 2>/dev/null | head -5 || true

# Install community node (needs python3/make/g++ — only available in Stage 1)
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Symlink system Chromium into Playwright's browser dir (prevents runtime download)
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    if [ -z "$CHROMIUM_DIR" ]; then \
      CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148"; \
    fi && \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/lib/chromium/chromium ${CHROMIUM_DIR}/chrome-linux/chrome && \
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    echo "#!/bin/sh" > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p ${BROWSER_BASE}/firefox-1511/linux && \
    touch ${BROWSER_BASE}/firefox-1511/linux/firefox && \
    chmod +x ${BROWSER_BASE}/firefox-1511/linux/firefox

# ── Stage 2: n8n base (distroless Alpine — NO apt-get, NO apk) ────────────────
FROM n8nio/n8n:${N8N_VERSION}
USER root

# ── Chromium: wrapper + actual binary + full lib dir ──────────────────────────
COPY --from=browser-installer /usr/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=browser-installer /usr/bin/chromium /usr/bin/chromium
COPY --from=browser-installer /usr/lib/chromium /usr/lib/chromium

# ── Xvfb binary ───────────────────────────────────────────────────────────────
COPY --from=browser-installer /usr/bin/Xvfb /usr/bin/Xvfb

# ── Runtime tools (distroless has none) ───────────────────────────────────────
COPY --from=browser-installer /usr/sbin/su-exec /usr/local/bin/su-exec
COPY --from=browser-installer /usr/bin/curl /usr/bin/curl

# ── Xvfb shared libs (previously missing → caused symbol not found) ───────────
COPY --from=browser-installer /usr/lib/libGL.so.1 /usr/lib/libGL.so.1
COPY --from=browser-installer /usr/lib/libGLX.so.0 /usr/lib/libGLX.so.0
COPY --from=browser-installer /usr/lib/libGLdispatch.so.0 /usr/lib/libGLdispatch.so.0
COPY --from=browser-installer /usr/lib/libpixman-1.so.0 /usr/lib/libpixman-1.so.0
COPY --from=browser-installer /usr/lib/libxfont2.so.2 /usr/lib/libxfont2.so.2
COPY --from=browser-installer /usr/lib/libXdmcp.so.6 /usr/lib/libXdmcp.so.6
COPY --from=browser-installer /usr/lib/libXau.so.6 /usr/lib/libXau.so.6
COPY --from=browser-installer /usr/lib/libX11.so.6 /usr/lib/libX11.so.6
COPY --from=browser-installer /usr/lib/libXext.so.6 /usr/lib/libXext.so.6
COPY --from=browser-installer /usr/lib/libXrender.so.1 /usr/lib/libXrender.so.1
COPY --from=browser-installer /usr/lib/libXfixes.so.3 /usr/lib/libXfixes.so.3

# ── Chromium shared libs ───────────────────────────────────────────────────────
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

# ── Pre-create ms-playwright cache dir (prevents runtime re-download) ──────────
RUN mkdir -p /home/node/.cache/ms-playwright/chromium-1148/chrome-linux && \
    ln -sf /usr/lib/chromium/chromium /home/node/.cache/ms-playwright/chromium-1148/chrome-linux/chrome

# ── Community node + permissions ──────────────────────────────────────────────
COPY --from=browser-installer /home/node/.n8n/custom /home/node/.n8n/custom
RUN chown -R node:node /home/node/.n8n /home/node/.cache

# ── App files ─────────────────────────────────────────────────────────────────
COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# ── Environment ───────────────────────────────────────────────────────────────
ENV N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    N8N_ENABLE_EXECUTE_COMMAND=false \
    NODES_EXCLUDE=[] \
    EXTERNAL_HOOK_FILES=/home/node/execution-hooks.js \
    N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom \
    N8N_ALLOWED_PATHS=/home/node/files \
    NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core \
    NODE_FUNCTION_ALLOW_BUILTIN=crypto,path,url \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/lib/chromium \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/lib/chromium/chromium \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/lib/chromium/chromium \
    N8N_COMMUNITY_PACKAGES_ENABLED=true \
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_PERSONALIZATION_ENABLED=false \
    N8N_HIRING_BANNER_ENABLED=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    DISPLAY=:99

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]
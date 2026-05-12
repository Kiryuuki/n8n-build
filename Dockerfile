ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine — install everything needed ───────────────────────────────
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

# Debug: show actual paths in CI logs — check these if next build fails
RUN echo "=== Chromium ===" && ls -la /usr/bin/chromium* /usr/lib/chromium/chromium 2>/dev/null || true && \
    echo "=== Xvfb ===" && ls -la /usr/bin/Xvfb 2>/dev/null || true && \
    echo "=== su-exec ===" && find / -name "su-exec" -not -path "*/proc/*" 2>/dev/null && \
    echo "=== curl ===" && which curl 2>/dev/null || true

# Stage 1b: collect all tools + libs into /export — no more hardcoded paths in Stage 2
RUN mkdir -p /export/bin /export/lib && \
    \
    # Copy binaries by finding them — path-agnostic
    cp $(which chromium-browser 2>/dev/null || find /usr -name chromium-browser -type f 2>/dev/null | head -1) /export/bin/chromium-browser 2>/dev/null || true && \
    cp $(find /usr/lib/chromium /usr/bin -name "chromium" -type f 2>/dev/null | head -1) /export/bin/chromium 2>/dev/null || true && \
    cp $(which Xvfb 2>/dev/null || find /usr -name Xvfb -type f 2>/dev/null | head -1) /export/bin/Xvfb 2>/dev/null || true && \
    cp $(find / -name "su-exec" -type f -not -path "*/proc/*" 2>/dev/null | head -1) /export/bin/su-exec 2>/dev/null || true && \
    cp $(which curl 2>/dev/null) /export/bin/curl 2>/dev/null || true && \
    \
    # Collect all matching .so files (real files, not symlinks) into flat /export/lib
    find /usr/lib /lib -name "*.so*" -type f \
      \( -name "libX*.so*" -o -name "libx*.so*" \
      -o -name "libGL*.so*" -o -name "libEGL*.so*" \
      -o -name "libpixman*.so*" \
      -o -name "libxfont*.so*" -o -name "libXfont*.so*" \
      -o -name "libfreetype*.so*" -o -name "libharfbuzz*.so*" \
      -o -name "libnss*.so*" -o -name "libnspr*.so*" \
      -o -name "libsmime*.so*" -o -name "libssl3*.so*" \
      -o -name "libplds*.so*" -o -name "libplc*.so*" \
      -o -name "libasound*.so*" -o -name "libdbus*.so*" \
      -o -name "libglib*.so*" -o -name "libgobject*.so*" -o -name "libgio*.so*" \
      -o -name "libpango*.so*" -o -name "libcairo*.so*" \
      -o -name "libgbm*.so*" -o -name "libxkbcommon*.so*" \
      -o -name "libatspi*.so*" -o -name "libcups*.so*" \
      -o -name "libdrm*.so*" -o -name "libstdc++*.so*" \
      -o -name "libgcc_s*.so*" -o -name "libnettle*.so*" \
      -o -name "libbsd*.so*" -o -name "libfontenc*.so*" \
      \) \
      -exec cp -n {} /export/lib/ \; && \
    \
    echo "=== /export/bin ===" && ls -la /export/bin/ && \
    echo "=== /export/lib count ===" && ls /export/lib/ | wc -l

# Install community node (needs python3/make/g++)
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Symlink system Chromium into Playwright browser dir (prevents runtime re-download)
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

# Binaries from export dir
COPY --from=browser-installer /export/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=browser-installer /export/bin/chromium /usr/bin/chromium
COPY --from=browser-installer /export/bin/Xvfb /usr/bin/Xvfb
COPY --from=browser-installer /export/bin/su-exec /usr/local/bin/su-exec
COPY --from=browser-installer /export/bin/curl /usr/bin/curl

# Full chromium lib dir
COPY --from=browser-installer /usr/lib/chromium /usr/lib/chromium

# All shared libs — single dir copy, no path guessing
COPY --from=browser-installer /export/lib/ /usr/lib/

# Pre-create ms-playwright cache dir (prevents runtime re-download attempt)
RUN mkdir -p /home/node/.cache/ms-playwright/chromium-1148/chrome-linux && \
    ln -sf /usr/lib/chromium/chromium /home/node/.cache/ms-playwright/chromium-1148/chrome-linux/chrome

# Community node + permissions
COPY --from=browser-installer /home/node/.n8n/custom /home/node/.n8n/custom
RUN chown -R node:node /home/node/.n8n /home/node/.cache

# App files
COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Environment
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
ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine 3.22 ───────────────────────────────────────────────────────
# All installs here — n8nio/n8n v2.1+ strips apk from the final image.
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
    dbus dbus-libs udev su-exec \
    libthai libdatrie

# Collect exact libs Chromium needs via ldd into a staging dir
RUN mkdir -p /chromium-libs && \
    ldd /usr/bin/chromium 2>/dev/null \
        | awk '/=>/{print $3}' \
        | grep '^/' \
        | sort -u \
        | xargs -I{} cp -L {} /chromium-libs/ && \
    find /usr/lib/chromium -name '*.so*' \
        -exec cp -L {} /chromium-libs/ \; 2>/dev/null || true

# Install community Playwright node
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Symlink system Chromium into the versioned path Playwright expects
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# Patch ALL setup-browsers files (both .ts source and compiled .js).
# n8n executes the compiled .js — patching only .ts has no effect at runtime.
RUN find /home/node/.n8n/custom/node_modules/n8n-nodes-playwright \
        \( -name "setup-browsers.ts" -o -name "setup-browsers.js" \) \
        -type f \
        | while read f; do \
            echo "// patched: system chromium used, browser download disabled" > "$f"; \
            echo "[BUILD] Patched $f"; \
          done

# ── Stage 2: n8n hardened image (no apk) ──────────────────────────────────────
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Chromium binary + wrapper script (chromium-browser is a shell script calling /usr/bin/chromium)
COPY --from=builder /usr/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=builder /usr/bin/chromium         /usr/bin/chromium
COPY --from=builder /usr/lib/chromium         /usr/lib/chromium

# All shared libs collected by ldd — no manual list, no missing .so surprises
COPY --from=builder /chromium-libs            /usr/lib/

# su-exec for privilege drop
COPY --from=builder /sbin/su-exec             /usr/local/bin/su-exec

# Fonts
COPY --from=builder /usr/share/fonts          /usr/share/fonts

# Pre-built community node (native addons compiled, setup-browsers patched)
COPY --from=builder /home/node/.n8n/custom    /home/node/.n8n/custom
RUN chown -R node:node /home/node/.n8n

COPY execution-hooks.js      /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENV \
    N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom \
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
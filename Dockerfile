ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine 3.22 — build everything here ──────────────────────────────
# n8nio/n8n v2.1+ strips apk. We install chromium + build the community node
# here, then COPY the outputs into Stage 2.
FROM alpine:3.22 AS builder

# All deps in one layer: build tools + chromium + runtime libs + utilities
RUN apk add --no-cache \
    # Native addon build tools (isolated-vm, sqlite3 in n8n-nodes-playwright)
    python3 make g++ nodejs npm \
    # Chromium + full dep tree (apk resolves transitive deps correctly)
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

# Collect exact libs Chromium needs via ldd — no manual .so list, no surprises
RUN mkdir -p /chromium-libs && \
    ldd /usr/bin/chromium 2>/dev/null \
        | awk '/=>/ { print $3 }' \
        | grep '^/' \
        | sort -u \
        | xargs -I{} cp -L {} /chromium-libs/ && \
    # Also grab any .so files bundled inside /usr/lib/chromium (swiftshader etc)
    find /usr/lib/chromium -name '*.so*' \
        -exec cp -L {} /chromium-libs/ \; 2>/dev/null || true

# Install n8n-nodes-playwright (needs python3/make/g++ for native addons)
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright --legacy-peer-deps && \
    npm cache clean --force

# Symlink system Chromium into the versioned path Playwright expects.
# This satisfies Playwright's binary check without downloading anything.
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    # Stub webkit + firefox so Playwright doesn't attempt to download them
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' \
        > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# Patch setup-browsers (.ts source AND compiled .js) to no-op.
# n8n executes the compiled .js — patching only .ts has no runtime effect.
# Without this patch the setup script re-runs on every start and fails.
RUN find /home/node/.n8n/custom/node_modules/n8n-nodes-playwright \
        \( -name "setup-browsers.ts" -o -name "setup-browsers.js" \) \
        -type f | while read f; do \
            echo "// patched: system chromium used, download disabled" > "$f"; \
        done

# ── Stage 2: n8n hardened image (apk stripped since v2.1) ─────────────────────
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Chromium binary (chromium-browser is a shell wrapper that calls /usr/bin/chromium)
COPY --from=builder /usr/bin/chromium-browser  /usr/bin/chromium-browser
COPY --from=builder /usr/bin/chromium          /usr/bin/chromium
COPY --from=builder /usr/lib/chromium          /usr/lib/chromium

# All shared libs collected by ldd — avoids manual list and missing .so errors
COPY --from=builder /chromium-libs             /usr/lib/

# su-exec for privilege drop in entrypoint
COPY --from=builder /sbin/su-exec              /usr/local/bin/su-exec

# Fonts
COPY --from=builder /usr/share/fonts           /usr/share/fonts

# Pre-built community node with patched setup-browsers and chromium symlink
COPY --from=builder /home/node/.n8n/custom     /home/node/.n8n/custom

RUN chown -R node:node /home/node/.n8n

COPY execution-hooks.js       /home/node/execution-hooks.js
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
# ─────────────────────────────────────────────────────────────────────────────
# n8n + Playwright (Chromium CDP) — single-stage Alpine build
#
# All dependencies installed in one stage — no cross-stage lib copying,
# no apk-stripped base image fighting. Works on Docker, Dokploy, LXC.
#
# Ports:  5678 — n8n UI
#         9222 — Chromium CDP (connect Playwright via ws://host:9222)
# ─────────────────────────────────────────────────────────────────────────────

ARG N8N_VERSION=2.19.5
ARG NODE_VERSION=20

FROM node:${NODE_VERSION}-alpine3.22

# Build args available after FROM
ARG N8N_VERSION

# ── System deps ───────────────────────────────────────────────────────────────
# Split into groups: build tools (removed after npm install), runtime libs, chromium
RUN apk add --no-cache \
    # Build tools for native addons (isolated-vm, sqlite3, bcrypt)
    python3 make g++ \
    # Chromium + its runtime deps (apk resolves the full dep tree)
    chromium \
    nss freetype harfbuzz ca-certificates \
    ttf-freefont font-noto-emoji \
    libstdc++ alsa-lib at-spi2-core \
    cups-libs libdrm libxcomposite libxdamage \
    libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs udev \
    # Utilities
    su-exec tini curl

# ── Install n8n globally ──────────────────────────────────────────────────────
# Run as root so npm can write to global dirs; we drop to node user at runtime.
# --legacy-peer-deps needed for optional AI/LangChain peer conflicts in n8n 2.x
RUN npm install -g n8n@${N8N_VERSION} --legacy-peer-deps && \
    npm cache clean --force

# ── Install n8n-nodes-playwright community node ───────────────────────────────
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright --legacy-peer-deps && \
    npm cache clean --force

# ── Wire Chromium so Playwright node skips its own browser download ───────────
# The community node looks for chrome in a versioned subdir of its browsers/ dir.
# We symlink the system Chromium there. Stub webkit/firefox to prevent download attempts.
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    # Stub webkit
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    # Stub firefox
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# ── Patch setup-browsers (both .ts and compiled .js) to no-op ─────────────────
# Without this patch, n8n re-runs browser setup on every start and fails
# because it can't sudo-install deps inside a container at runtime.
RUN find /home/node/.n8n/custom/node_modules/n8n-nodes-playwright \
        \( -name "setup-browsers.ts" -o -name "setup-browsers.js" \) \
        -type f | while read f; do \
            echo "// patched: system chromium used, browser download disabled" > "$f"; \
            echo "[BUILD] Patched $f"; \
        done

# ── Remove build tools to shrink final image ──────────────────────────────────
# python3/make/g++ only needed for npm install native addon compilation
RUN apk del make g++

# ── Permissions ───────────────────────────────────────────────────────────────
RUN chown -R node:node /home/node/.n8n

# ── App files ─────────────────────────────────────────────────────────────────
COPY execution-hooks.js      /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# ── Environment ───────────────────────────────────────────────────────────────
ENV \
    # n8n timeouts (ms / seconds)
    N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    # Tell Playwright to use system Chromium, skip any download
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    # n8n custom node location + execution hooks
    N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom \
    EXTERNAL_HOOK_FILES=/home/node/execution-hooks.js \
    N8N_ALLOWED_PATHS=/home/node/files \
    # Allow playwright modules in Code nodes
    NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core \
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    N8N_ENABLE_EXECUTE_COMMAND=true \
    # Community packages
    N8N_COMMUNITY_PACKAGES_ENABLED=true \
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
    # Reduce noise
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_PERSONALIZATION_ENABLED=false \
    N8N_HIRING_BANNER_ENABLED=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

EXPOSE 5678 9222

# tini as PID 1 for proper signal handling and zombie reaping
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
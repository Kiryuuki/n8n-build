ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine — build Chromium env + community node ─────────────────────
# Must use same Alpine version as n8nio/base to ensure musl ABI compatibility.
FROM alpine:3.22 AS builder

# Build tools + Chromium + all runtime libs Chromium needs
RUN apk add --no-cache \
    python3 make g++ nodejs npm \
    chromium \
    nss freetype harfbuzz ca-certificates \
    ttf-freefont font-noto-emoji \
    libstdc++ alsa-lib at-spi2-core \
    cups-libs libdrm libxcomposite libxdamage \
    libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs udev

# Install community Playwright node where build tools are available
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Symlink system Chromium so Playwright node skips its own browser download.
# The setup-browsers script checks for chrome binary; symlink satisfies the check.
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    # Find the chromium dir (versioned), create if not present
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    # Stub out webkit + firefox so Playwright doesn't try to download them
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# Patch the Playwright community node's setup script to be a no-op at runtime.
# Without this, n8n re-runs setup-browsers.ts on every start and fails because
# it can't sudo-install deps or write to /usr/bin inside a container.
RUN SETUP_SCRIPT=$(find /home/node/.n8n/custom/node_modules/n8n-nodes-playwright \
        -name "setup-browsers*" -type f 2>/dev/null | head -n 1) && \
    if [ -n "$SETUP_SCRIPT" ]; then \
        echo "// patched: browser setup disabled, system chromium used via symlink" > "$SETUP_SCRIPT"; \
    fi

# ── Stage 2: Final image (same Alpine 3.22 base as n8nio/n8n) ─────────────────
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install Chromium and its runtime dependencies directly in the final image.
# This is simpler and more correct than cross-copying individual .so files —
# Alpine's apk resolves the full dependency tree without ABI guesswork.
RUN apk add --no-cache \
    chromium \
    nss freetype harfbuzz ca-certificates \
    ttf-freefont font-noto-emoji \
    libstdc++ alsa-lib at-spi2-core \
    cups-libs libdrm libxcomposite libxdamage \
    libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs udev \
    su-exec

# Copy pre-built community node from builder (avoids re-compiling native addons)
COPY --from=builder /home/node/.n8n/custom /home/node/.n8n/custom

RUN chown -R node:node /home/node/.n8n

# Copy app files
COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# ── Environment ───────────────────────────────────────────────────────────────
ENV \
    # Timeouts
    N8N_DEFAULT_TIMEOUT=900000 \
    EXECUTIONS_TIMEOUT=3600 \
    EXECUTIONS_TIMEOUT_MAX=7200 \
    # Playwright: use system Chromium, skip any download attempts
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    # n8n custom node + hooks
    N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom \
    EXTERNAL_HOOK_FILES=/home/node/execution-hooks.js \
    N8N_ALLOWED_PATHS=/home/node/files \
    # Allow external modules used by Playwright node
    NODE_FUNCTION_ALLOW_EXTERNAL=playwright,playwright-core \
    NODE_FUNCTION_ALLOW_BUILTIN=* \
    N8N_ENABLE_EXECUTE_COMMAND=true \
    # Community packages
    N8N_COMMUNITY_PACKAGES_ENABLED=true \
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
    # Disable telemetry/noise
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_PERSONALIZATION_ENABLED=false \
    N8N_HIRING_BANNER_ENABLED=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]
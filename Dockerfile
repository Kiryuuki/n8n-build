ARG N8N_VERSION=1.70.0
# Note: Use a specific version like 1.70.0 for reproducibility. 

# ── Stage 1: Alpine — install Chromium + build community node ─────────────────
FROM alpine:3.22 AS browser-installer

# Build tools needed for native node addons (isolated-vm etc)
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    nodejs \
    npm \
    chromium \
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

# Install community node here where python3/make/g++ are available
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# ── Stage 2: n8n hardened image (Debian based) ────────────────────────────────
FROM n8nio/n8n:${N8N_VERSION}
USER root

# Fix Issue #7: Install Xvfb and dependencies from the base image's own package manager
# This avoids cross-distro shared library errors.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    dbus \
    su-exec \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Fix Issue #8: Copy actual Chromium binaries and libs from Alpine stage
# We copy the entire chromium directory and the main binary.
COPY --from=browser-installer /usr/bin/chromium /usr/bin/chromium
COPY --from=browser-installer /usr/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=browser-installer /usr/lib/chromium /usr/lib/chromium

# Copy essential shared libs from Alpine stage (musl based)
# NOTE: This is still a bit risky on a glibc system, but we follow the working reference pattern.
COPY --from=browser-installer /usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6
COPY --from=browser-installer /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1

# Fix Issue #9: Pre-create ms-playwright cache dir and symlink system Chromium
# This prevents Playwright from attempting to download browsers at runtime.
RUN mkdir -p /home/node/.cache/ms-playwright/chromium-1148/chrome-linux && \
    ln -sf /usr/bin/chromium-browser /home/node/.cache/ms-playwright/chromium-1148/chrome-linux/chrome && \
    chown -R node:node /home/node/.cache

# Copy pre-built community node from Alpine stage
COPY --from=browser-installer /home/node/.n8n/custom /home/node/.n8n/custom
RUN chown -R node:node /home/node/.n8n

# Copy hooks and entrypoint
COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Environment variables (Optimized for Security and Stability)
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
    PLAYWRIGHT_BROWSERS_PATH=/usr/bin \
    PLAYWRIGHT_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    N8N_COMMUNITY_PACKAGES_ENABLED=true \
    N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_PERSONALIZATION_ENABLED=false \
    N8N_HIRING_BANNER_ENABLED=false \
    N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
    DISPLAY=:99

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]

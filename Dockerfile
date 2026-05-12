ARG N8N_VERSION=2.19.5
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install system dependencies
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
    su-exec

# Pre-install community node at build time
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npx playwright install chromium --with-deps || true && \
    npm cache clean --force

# Symlink system Chromium for Playwright (matches reference LXC logic)
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    mkdir -p ${BROWSER_BASE}/chromium-1148/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${BROWSER_BASE}/chromium-1148/chrome-linux/chrome && \
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    touch "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
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
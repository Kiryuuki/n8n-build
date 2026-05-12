ARG N8N_VERSION=2.19.5
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Install system dependencies
RUN apk add --no-cache \
    chromium \
    xvfb \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    dbus \
    su-exec

# Pre-install community node at build time
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npx playwright install chromium --with-deps || true && \
    npm cache clean --force

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
    DISPLAY=:99

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]

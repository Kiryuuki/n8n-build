ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine 3.22 — matches n8nio/base, has apk ───────────────────────
# We do ALL package installation here. Stage 2 (n8nio/n8n) has apk stripped
# since v2.1.0 as a hardening measure, so we must COPY binaries/libs across.
FROM alpine:3.22 AS builder

# Build tools + Chromium + every lib Chromium needs at runtime
RUN apk add --no-cache \
    # Build tools for native node addons (isolated-vm, sqlite3, etc.)
    python3 make g++ \
    # Node for npm install
    nodejs npm \
    # Chromium and its direct deps
    chromium \
    chromium-swiftshader \
    nss freetype harfbuzz ca-certificates \
    ttf-freefont font-noto-emoji \
    # Runtime libs Chromium links against
    libstdc++ libgcc alsa-lib at-spi2-core \
    cups-libs libdrm libxcomposite libxdamage \
    libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs udev \
    # su-exec for dropping privileges in entrypoint
    su-exec

# Install community Playwright node (needs python3/make/g++ for native addons)
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Symlink system Chromium into the versioned path Playwright expects.
# This prevents Playwright from trying to download its own browser at runtime.
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    [ -z "$CHROMIUM_DIR" ] && CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148" ; \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/bin/chromium-browser ${CHROMIUM_DIR}/chrome-linux/chrome && \
    # Stub webkit + firefox so Playwright doesn't attempt downloading them
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p "${BROWSER_BASE}/firefox-1511/linux" && \
    printf '#!/bin/sh\nexit 0\n' > "${BROWSER_BASE}/firefox-1511/linux/firefox" && \
    chmod +x "${BROWSER_BASE}/firefox-1511/linux/firefox"

# Patch the setup-browsers script to a no-op so n8n doesn't re-run it on
# every container start (it fails without root + internet access at runtime).
RUN SETUP=$(find /home/node/.n8n/custom/node_modules/n8n-nodes-playwright \
        -name "setup-browsers*" -type f 2>/dev/null | head -n 1) && \
    [ -n "$SETUP" ] && \
    echo "// patched: system chromium used, browser download disabled" > "$SETUP" || true

# ── Stage 2: n8n hardened image (no apk) ──────────────────────────────────────
FROM n8nio/n8n:${N8N_VERSION}

USER root

# Copy Chromium binary and its wrapper script
COPY --from=builder /usr/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=builder /usr/bin/chromium /usr/bin/chromium
COPY --from=builder /usr/lib/chromium /usr/lib/chromium

# Copy su-exec for privilege dropping in entrypoint
COPY --from=builder /sbin/su-exec /usr/local/bin/su-exec

# Copy all shared libs Chromium needs.
# Using directory-level COPY avoids missing transitive deps.
COPY --from=builder /usr/lib/libstdc++.so.6       /usr/lib/libstdc++.so.6
COPY --from=builder /usr/lib/libgcc_s.so.1        /usr/lib/libgcc_s.so.1
COPY --from=builder /usr/lib/libdbus-1.so.3       /usr/lib/libdbus-1.so.3
COPY --from=builder /usr/lib/libnss3.so           /usr/lib/libnss3.so
COPY --from=builder /usr/lib/libnssutil3.so       /usr/lib/libnssutil3.so
COPY --from=builder /usr/lib/libsmime3.so         /usr/lib/libsmime3.so
COPY --from=builder /usr/lib/libssl3.so           /usr/lib/libssl3.so
COPY --from=builder /usr/lib/libplds4.so          /usr/lib/libplds4.so
COPY --from=builder /usr/lib/libplc4.so           /usr/lib/libplc4.so
COPY --from=builder /usr/lib/libnspr4.so          /usr/lib/libnspr4.so
COPY --from=builder /usr/lib/libfreetype.so.6     /usr/lib/libfreetype.so.6
COPY --from=builder /usr/lib/libharfbuzz.so.0     /usr/lib/libharfbuzz.so.0
COPY --from=builder /usr/lib/libasound.so.2       /usr/lib/libasound.so.2
COPY --from=builder /usr/lib/libglib-2.0.so.0     /usr/lib/libglib-2.0.so.0
COPY --from=builder /usr/lib/libgobject-2.0.so.0  /usr/lib/libgobject-2.0.so.0
COPY --from=builder /usr/lib/libgio-2.0.so.0      /usr/lib/libgio-2.0.so.0
COPY --from=builder /usr/lib/libgmodule-2.0.so.0  /usr/lib/libgmodule-2.0.so.0
COPY --from=builder /usr/lib/libpango-1.0.so.0    /usr/lib/libpango-1.0.so.0
COPY --from=builder /usr/lib/libpangocairo-1.0.so.0 /usr/lib/libpangocairo-1.0.so.0
COPY --from=builder /usr/lib/libpangoft2-1.0.so.0 /usr/lib/libpangoft2-1.0.so.0
COPY --from=builder /usr/lib/libcairo.so.2        /usr/lib/libcairo.so.2
COPY --from=builder /usr/lib/libcairo-gobject.so.2 /usr/lib/libcairo-gobject.so.2
COPY --from=builder /usr/lib/libgbm.so.1          /usr/lib/libgbm.so.1
COPY --from=builder /usr/lib/libxkbcommon.so.0    /usr/lib/libxkbcommon.so.0
COPY --from=builder /usr/lib/libatspi.so.0        /usr/lib/libatspi.so.0
COPY --from=builder /usr/lib/libcups.so.2         /usr/lib/libcups.so.2
COPY --from=builder /usr/lib/libdrm.so.2          /usr/lib/libdrm.so.2
COPY --from=builder /usr/lib/libpixman-1.so.0     /usr/lib/libpixman-1.so.0
COPY --from=builder /usr/lib/libfontconfig.so.1   /usr/lib/libfontconfig.so.1
COPY --from=builder /usr/lib/libexpat.so.1        /usr/lib/libexpat.so.1
COPY --from=builder /usr/lib/libffi.so.8          /usr/lib/libffi.so.8
COPY --from=builder /usr/lib/libpcre2-8.so.0      /usr/lib/libpcre2-8.so.0
COPY --from=builder /usr/lib/libmount.so.1        /usr/lib/libmount.so.1
COPY --from=builder /usr/lib/libblkid.so.1        /usr/lib/libblkid.so.1
COPY --from=builder /usr/lib/libuuid.so.1         /usr/lib/libuuid.so.1
COPY --from=builder /usr/lib/libz.so.1            /usr/lib/libz.so.1
COPY --from=builder /usr/lib/libbz2.so.1          /usr/lib/libbz2.so.1
COPY --from=builder /usr/lib/libpng16.so.16       /usr/lib/libpng16.so.16
COPY --from=builder /usr/lib/libgraphite2.so.3    /usr/lib/libgraphite2.so.3
COPY --from=builder /usr/lib/libthai.so.0         /usr/lib/libthai.so.0
COPY --from=builder /usr/lib/libdatrie.so.1       /usr/lib/libdatrie.so.1
COPY --from=builder /usr/lib/libXcomposite.so.1   /usr/lib/libXcomposite.so.1
COPY --from=builder /usr/lib/libXdamage.so.1      /usr/lib/libXdamage.so.1
COPY --from=builder /usr/lib/libXfixes.so.3       /usr/lib/libXfixes.so.3
COPY --from=builder /usr/lib/libXrandr.so.2       /usr/lib/libXrandr.so.2
COPY --from=builder /usr/lib/libXrender.so.1      /usr/lib/libXrender.so.1
COPY --from=builder /usr/lib/libXext.so.6         /usr/lib/libXext.so.6
COPY --from=builder /usr/lib/libX11.so.6          /usr/lib/libX11.so.6
COPY --from=builder /usr/lib/libxcb.so.1          /usr/lib/libxcb.so.1
COPY --from=builder /usr/lib/libXau.so.6          /usr/lib/libXau.so.6
COPY --from=builder /usr/lib/libXdmcp.so.6        /usr/lib/libXdmcp.so.6
# Font dirs needed by Chromium
COPY --from=builder /usr/share/fonts              /usr/share/fonts

# Copy pre-built community node (native addons already compiled in builder)
COPY --from=builder /home/node/.n8n/custom /home/node/.n8n/custom
RUN chown -R node:node /home/node/.n8n

# Copy hooks and entrypoint
COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# ── Environment ───────────────────────────────────────────────────────────────
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
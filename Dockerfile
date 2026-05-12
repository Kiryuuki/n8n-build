ARG N8N_VERSION=2.19.5

# ── Stage 1: Alpine 3.22 builder ──────────────────────────────────────────────
# n8nio/base IS Alpine 3.22 + musl — same libc, binaries are compatible.
# apk is stripped from the n8n image so we install everything here and copy over.
FROM alpine:3.22 AS builder

RUN apk add --no-cache \
    python3 make g++ nodejs npm \
    chromium xvfb \
    mesa-gl \
    nss freetype harfbuzz \
    ca-certificates ttf-freefont font-noto-emoji \
    udev libstdc++ alsa-lib at-spi2-core cups-libs libdrm \
    libxcomposite libxdamage libxfixes libxkbcommon libxrandr \
    mesa-gbm pango cairo glib gtk+3.0 \
    dbus dbus-libs \
    su-exec curl

# Print exact paths into build log — reference these if Stage 2 COPY fails
RUN echo "=== BIN ===" && \
    ls -la /usr/bin/chromium-browser /usr/bin/chromium /usr/bin/Xvfb /usr/bin/curl && \
    ls -la /usr/lib/chromium/chromium && \
    echo "=== SU-EXEC ===" && find / -name su-exec -not -path "*/proc/*" 2>/dev/null && \
    echo "=== KEY LIBS ===" && \
    ls /usr/lib/libGL.so.1 \
       /usr/lib/libpixman-1.so.0 \
       /usr/lib/libXfont2.so.2 \
       /usr/lib/libXdmcp.so.6 \
       /usr/lib/libXau.so.6 \
       /usr/lib/libnettle.so.8 \
       /usr/lib/libfontenc.so.1 2>/dev/null || echo "some libs missing — check paths above"

# Community node
RUN mkdir -p /home/node/.n8n/custom && \
    cd /home/node/.n8n/custom && \
    npm install n8n-nodes-playwright && \
    npm cache clean --force

# Wire Playwright → system Chromium (both paths the node checks)
RUN BROWSER_BASE=/home/node/.n8n/custom/node_modules/n8n-nodes-playwright/dist/nodes/browsers && \
    CHROMIUM_DIR=$(ls -d ${BROWSER_BASE}/chromium-* 2>/dev/null | head -n 1) && \
    if [ -z "$CHROMIUM_DIR" ]; then CHROMIUM_DIR="${BROWSER_BASE}/chromium-1148"; fi && \
    mkdir -p ${CHROMIUM_DIR}/chrome-linux && \
    ln -sf /usr/lib/chromium/chromium ${CHROMIUM_DIR}/chrome-linux/chrome && \
    mkdir -p "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk" && \
    printf '#!/bin/sh\n' > "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    chmod +x "${BROWSER_BASE}/webkit-2272/webkit-1/minibrowser-gtk/pw_run.sh" && \
    mkdir -p ${BROWSER_BASE}/firefox-1511/linux && \
    touch ${BROWSER_BASE}/firefox-1511/linux/firefox && \
    chmod +x ${BROWSER_BASE}/firefox-1511/linux/firefox && \
    mkdir -p /home/node/.cache/ms-playwright/chromium-1148/chrome-linux && \
    ln -sf /usr/lib/chromium/chromium /home/node/.cache/ms-playwright/chromium-1148/chrome-linux/chrome

# ── Stage 2: n8n distroless Alpine base ───────────────────────────────────────
FROM n8nio/n8n:${N8N_VERSION}
USER root

# Binaries
COPY --from=builder /usr/bin/chromium-browser /usr/bin/chromium-browser
COPY --from=builder /usr/bin/chromium /usr/bin/chromium
COPY --from=builder /usr/bin/Xvfb /usr/bin/Xvfb
COPY --from=builder /usr/bin/curl /usr/bin/curl
COPY --from=builder /usr/lib/chromium /usr/lib/chromium
COPY --from=builder /sbin/su-exec /usr/local/bin/su-exec

# Shared libs — same musl/Alpine 3.22, fully compatible
COPY --from=builder /usr/lib/libGL.so.1 /usr/lib/libGL.so.1
COPY --from=builder /usr/lib/libGLdispatch.so.0 /usr/lib/libGLdispatch.so.0
COPY --from=builder /usr/lib/libpixman-1.so.0 /usr/lib/libpixman-1.so.0
COPY --from=builder /usr/lib/libXfont2.so.2 /usr/lib/libXfont2.so.2
COPY --from=builder /usr/lib/libXdmcp.so.6 /usr/lib/libXdmcp.so.6
COPY --from=builder /usr/lib/libXau.so.6 /usr/lib/libXau.so.6
COPY --from=builder /usr/lib/libX11.so.6 /usr/lib/libX11.so.6
COPY --from=builder /usr/lib/libXext.so.6 /usr/lib/libXext.so.6
COPY --from=builder /usr/lib/libXfixes.so.3 /usr/lib/libXfixes.so.3
COPY --from=builder /usr/lib/libXrender.so.1 /usr/lib/libXrender.so.1
COPY --from=builder /usr/lib/libXxf86vm.so.1 /usr/lib/libXxf86vm.so.1
COPY --from=builder /usr/lib/libxcb.so.1 /usr/lib/libxcb.so.1
COPY --from=builder /usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6
COPY --from=builder /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1
COPY --from=builder /usr/lib/libdbus-1.so.3 /usr/lib/libdbus-1.so.3
COPY --from=builder /usr/lib/libnss3.so /usr/lib/libnss3.so
COPY --from=builder /usr/lib/libnssutil3.so /usr/lib/libnssutil3.so
COPY --from=builder /usr/lib/libsmime3.so /usr/lib/libsmime3.so
COPY --from=builder /usr/lib/libssl3.so /usr/lib/libssl3.so
COPY --from=builder /usr/lib/libplds4.so /usr/lib/libplds4.so
COPY --from=builder /usr/lib/libplc4.so /usr/lib/libplc4.so
COPY --from=builder /usr/lib/libnspr4.so /usr/lib/libnspr4.so
COPY --from=builder /usr/lib/libfreetype.so.6 /usr/lib/libfreetype.so.6
COPY --from=builder /usr/lib/libharfbuzz.so.0 /usr/lib/libharfbuzz.so.0
COPY --from=builder /usr/lib/libasound.so.2 /usr/lib/libasound.so.2
COPY --from=builder /usr/lib/libglib-2.0.so.0 /usr/lib/libglib-2.0.so.0
COPY --from=builder /usr/lib/libgobject-2.0.so.0 /usr/lib/libgobject-2.0.so.0
COPY --from=builder /usr/lib/libgio-2.0.so.0 /usr/lib/libgio-2.0.so.0
COPY --from=builder /usr/lib/libpango-1.0.so.0 /usr/lib/libpango-1.0.so.0
COPY --from=builder /usr/lib/libcairo.so.2 /usr/lib/libcairo.so.2
COPY --from=builder /usr/lib/libgbm.so.1 /usr/lib/libgbm.so.1
COPY --from=builder /usr/lib/libxkbcommon.so.0 /usr/lib/libxkbcommon.so.0
COPY --from=builder /usr/lib/libatspi.so.0 /usr/lib/libatspi.so.0
COPY --from=builder /usr/lib/libcups.so.2 /usr/lib/libcups.so.2
COPY --from=builder /usr/lib/libdrm.so.2 /usr/lib/libdrm.so.2
COPY --from=builder /usr/lib/libnettle.so.8 /usr/lib/libnettle.so.8
COPY --from=builder /usr/lib/libfontenc.so.1 /usr/lib/libfontenc.so.1
COPY --from=builder /usr/lib/libbsd.so.0 /usr/lib/libbsd.so.0
COPY --from=builder /usr/lib/libmd.so.0 /usr/lib/libmd.so.0

# Community node + playwright cache
COPY --from=builder /home/node/.n8n/custom /home/node/.n8n/custom
COPY --from=builder /home/node/.cache /home/node/.cache
RUN chown -R node:node /home/node/.n8n /home/node/.cache

COPY execution-hooks.js /home/node/execution-hooks.js
COPY --chmod=755 entrypoint.sh /entrypoint.sh

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
    # Ensure musl linker finds copied libs
    LD_LIBRARY_PATH=/usr/lib \
    DISPLAY=:99

EXPOSE 5678 9222

ENTRYPOINT ["/entrypoint.sh"]
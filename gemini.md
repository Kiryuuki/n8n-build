# gemini.md — Agent Build Instructions
# Project: n8n-playwright Docker Image with CI/CD
# Author: Minis (for Aldrin)
# Goal: Single self-contained Docker image. Deploy with only docker-compose.yml + .env.
#       CI/CD via GitHub Actions. n8n version bumps via single env var change.
# Updated: hooks.js provided by Aldrin (do NOT regenerate), community node baked in image.

---

## AGENT RULES

- Execute tasks in order. Do NOT skip ahead.
- Each task has a CHECKLIST. Every item must be ✅ before moving to next task.
- If a test fails, fix and re-test before continuing.
- Do not regenerate files marked as PROVIDED.
- Ask Aldrin only if a secret value or file path is missing.

---

## PROVIDED FILES (do not recreate)

- `execution-hooks.js` — already written by Aldrin. COPY as-is into image.
  - Pushes to Supabase table: `n8n_execution_logs`
  - Columns: `execution_id`, `workflow_name`, `status`
  - Uses native `fetch` (Node 18+), no SDK needed

---

## REPO STRUCTURE (create exactly this)

```
n8n-playwright/
├── .github/
│   └── workflows/
│       └── docker-publish.yml
├── Dockerfile
├── entrypoint.sh
├── execution-hooks.js          ← PROVIDED by Aldrin, just COPY here
├── docker-compose.yml
├── .env.example
├── .dockerignore
└── README.md
```

---

## PHASE 1 — Dockerfile

### TASK 1.1 — Write Dockerfile

**Requirements:**

- Base: `n8nio/n8n:${N8N_VERSION}`
- `ARG N8N_VERSION=2.19.5` at top — CI passes this for version bumps
- `USER root` for all installs
- `apk add --no-cache`: `chromium xvfb nss freetype harfbuzz ca-certificates ttf-freefont dbus su-exec`
- Pre-install community node at build time (avoids runtime hang + disk fill):
  ```dockerfile
  RUN mkdir -p /home/node/.n8n/custom && \
      cd /home/node/.n8n/custom && \
      npm install n8n-nodes-playwright && \
      npx playwright install chromium --with-deps || true
  ```
  Note: `|| true` because system Chromium already present; browser download may be skipped or fail harmlessly.
- `COPY execution-hooks.js /home/node/execution-hooks.js`
- `COPY entrypoint.sh /entrypoint.sh`
- `RUN chmod +x /entrypoint.sh`
- Bake all static ENV vars (listed below)
- `EXPOSE 5678 9222`
- `ENTRYPOINT ["/entrypoint.sh"]`

**ENV vars to bake into image:**
```dockerfile
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
```

**CHECKLIST — do not proceed until all pass:**
- [x] `docker build --build-arg N8N_VERSION=2.19.5 -t n8n-playwright:test .` exits 0
- [x] `docker image ls n8n-playwright:test` shows image
- [x] `docker run --rm n8n-playwright:test which chromium-browser` returns a path
- [x] `docker run --rm n8n-playwright:test ls /home/node/execution-hooks.js` returns file
- [x] `docker run --rm n8n-playwright:test ls /home/node/.n8n/custom/node_modules/n8n-nodes-playwright` returns directory

---

### TASK 1.2 — Write entrypoint.sh

**Logic (strict order):**

```bash
#!/bin/sh
set -e

# 1. Start Xvfb virtual display
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
sleep 2

# 2. Start Chromium with CDP in background
chromium-browser \
  --remote-debugging-port=9222 \
  --remote-debugging-address=0.0.0.0 \
  --no-sandbox \
  --disable-dev-shm-usage \
  --disable-gpu \
  --headless \
  --user-data-dir=/tmp/chrome-data \
  &

sleep 1
echo "[ENTRYPOINT] Xvfb PID: $XVFB_PID"
echo "[ENTRYPOINT] Chrome CDP listening on :9222"
echo "[ENTRYPOINT] Starting n8n as node user..."

# 3. Hand off to n8n as node user
exec su-exec node n8n start
```

**CHECKLIST — do not proceed until all pass:**
- [x] Container starts without immediate exit
- [x] `docker logs n8n-test` shows `[ENTRYPOINT] Chrome CDP listening on :9222`
- [x] `docker logs n8n-test` shows `[HOOK] n8n IS READY AND HOOKS ARE ACTIVE`
- [x] `curl -s -o /dev/null -w "%{http_code}" http://localhost:5678` returns `200`
- [x] `curl -s http://localhost:9222/json/version` returns JSON with `browserVersion` key
- [x] Run `docker stop n8n-test` to clean up

---

## PHASE 2 — Compose + Env

### TASK 2.1 — Write docker-compose.yml

```yaml
services:
  n8n:
    image: ghcr.io/YOUR_GITHUB_USERNAME/n8n-playwright:latest
    container_name: n8n-playwright
    restart: unless-stopped
    env_file: .env
    ports:
      - "5678:5678"
      - "9222:9222"
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_files:/home/node/files

volumes:
  n8n_data:
  n8n_files:
```

Replace `YOUR_GITHUB_USERNAME` with actual GitHub username before committing.

**CHECKLIST:**
- [x] `docker compose config` passes with no errors

---

### TASK 2.2 — Write .env.example

```env
# n8n Playwright Stack — cp .env.example .env, fill values, never commit .env

# Cloudflare tunnel or domain
WEBHOOK_URL=https://your-tunnel.kiryuuki.space

# Supabase — hooks push to n8n_execution_logs table
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your_service_role_key_here

# n8n encryption key (generate: openssl rand -hex 32)
N8N_ENCRYPTION_KEY=your_32char_hex_key_here
```

**CHECKLIST:**
- [x] File created at `.env.example`
- [x] No real secrets in file

---

### TASK 2.3 — Write .dockerignore

```
.env
.env.*
!.env.example
.git
.github
node_modules
*.log
```

**CHECKLIST:**
- [x] File created

---

## PHASE 3 — Supabase Migration

### TASK 3.1 — Write supabase_migration.sql

```sql
-- Matches execution-hooks.js: pushes execution_id, workflow_name, status
CREATE TABLE IF NOT EXISTS n8n_execution_logs (
  id             BIGSERIAL PRIMARY KEY,
  execution_id   TEXT,
  workflow_name  TEXT,
  status         TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exec_logs_workflow ON n8n_execution_logs (workflow_name);
CREATE INDEX IF NOT EXISTS idx_exec_logs_status   ON n8n_execution_logs (status);
CREATE INDEX IF NOT EXISTS idx_exec_logs_created  ON n8n_execution_logs (created_at DESC);
```

**CHECKLIST:**
- [x] File created at `supabase_migration.sql`
- [ ] Agent does NOT run this — Aldrin runs manually in Supabase SQL Editor

---

## PHASE 4 — CI/CD (GitHub Actions)

### TASK 4.1 — Write docker-publish.yml

File: `.github/workflows/docker-publish.yml`

**Trigger rules:**
- Push to `main` → build + push tagged `latest`
- Push tag `v*` → build + push tagged with semver AND `latest`
- PR to `main` → build only, no push (validation gate)

**N8N version strategy:**
- Dockerfile uses `ARG N8N_VERSION=2.19.5`
- CI reads from GitHub repo variable `vars.N8N_VERSION`, falls back to `2.19.5`
- Pass via `--build-arg N8N_VERSION=${{ vars.N8N_VERSION || '2.19.5' }}`
- **To upgrade n8n:** update `N8N_VERSION` in GitHub repo Settings → Variables → Actions → re-run workflow

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]

permissions:
  contents: read
  packages: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU (multi-arch)
        uses: docker/setup-qemu-action@v3

      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/n8n-playwright
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            N8N_VERSION=${{ vars.N8N_VERSION || '2.19.5' }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**CHECKLIST:**
- [x] File valid YAML
- [ ] Push to GitHub main branch
- [ ] GitHub Actions tab shows workflow triggered
- [ ] Build job passes (green check)
- [ ] Image visible at `ghcr.io/YOUR_USERNAME/n8n-playwright` in GitHub Packages tab

---

### TASK 4.2 — Write README.md

**Required sections:**
1. **Overview** — n8n + Chromium CDP + execution hooks + community Playwright node, single image
2. **Quick Start** — 5 steps: clone → cp .env.example .env → fill .env → run supabase_migration.sql → docker compose up -d
3. **Ports** — `5678` n8n UI, `9222` Chrome CDP
4. **Connect Playwright to CDP** — `ws://localhost:9222` (host) or `ws://n8n-playwright:9222` (internal)
5. **Playwright Community Node** — pre-installed as `n8n-nodes-playwright`, available in n8n node picker after restart
6. **Upgrade n8n** — update `N8N_VERSION` in GitHub repo Variables → re-run CI → `docker compose pull && docker compose up -d`
7. **Execution Hooks** — run `supabase_migration.sql` first, set `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` in `.env`
8. **Local Build** — `docker build --build-arg N8N_VERSION=2.19.5 -t n8n-playwright .`

**CHECKLIST:**
- [x] All 8 sections present
- [x] CDP connect string correct

---

## PHASE 5 — Final Validation

### TASK 5.1 — Full smoke test with real .env values

**Run in order. Stop on first failure, fix, re-run from that step.**

```bash
# 1. Build final image
docker build --build-arg N8N_VERSION=2.19.5 -t n8n-playwright:final .

# 2. Start with real .env
docker compose up -d

# 3. Wait for boot
sleep 15

# 4. n8n UI reachable
curl -s -o /dev/null -w "%{http_code}" http://localhost:5678
# Expected: 200

# 5. CDP reachable
curl -s http://localhost:9222/json/version
# Expected: JSON with browserVersion

# 6. Hook fired on boot
docker logs n8n-playwright 2>&1 | grep "n8n IS READY AND HOOKS ARE ACTIVE"
# Expected: line found

# 7. Community node present in container
docker exec n8n-playwright ls /home/node/.n8n/custom/node_modules/n8n-nodes-playwright
# Expected: directory listing

# 8. Trigger a test workflow execution in n8n UI, then check Supabase
# n8n_execution_logs table should have a new row
```

**CHECKLIST:**
- [ ] Step 4 → `200`
- [ ] Step 5 → valid JSON with `browserVersion`
- [ ] Step 6 → log line found
- [ ] Step 7 → directory exists
- [ ] Step 8 → Supabase `n8n_execution_logs` has a new row after test workflow run

---

### TASK 5.2 — Push to GitHub and verify CI

```bash
git init
git remote add origin https://github.com/YOUR_USERNAME/n8n-playwright.git
git add .
git commit -m "feat: n8n-playwright image with Chromium CDP, community node, execution hooks, CI/CD"
git push -u origin main
```

**CHECKLIST:**
- [ ] Push succeeds
- [ ] GitHub Actions workflow triggers automatically
- [ ] Build + push job green
- [ ] Image visible in GitHub Packages (`ghcr.io/YOUR_USERNAME/n8n-playwright:latest`)
- [ ] Pull image on target server: `docker pull ghcr.io/YOUR_USERNAME/n8n-playwright:latest`
- [ ] `docker compose up -d` on server uses new image successfully

---

## N8N UPGRADE PROCEDURE (post-deploy, zero code changes)

```
1. GitHub repo → Settings → Variables → Actions
2. Set N8N_VERSION = 2.X.X
3. Actions → docker-publish → Run workflow → main
4. On server: docker compose pull && docker compose up -d
```

---

## RISK TABLE

| Risk | Mitigation |
|------|-----------|
| `n8n-nodes-playwright` tries to download Chromium at build | `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` + `\|\| true` on npm install |
| su-exec not found in base image | Explicitly `apk add su-exec` in Dockerfile |
| Xvfb starts after Chromium | `sleep 2` after Xvfb in entrypoint.sh |
| Hook file not loaded | `EXTERNAL_HOOK_FILES` baked in ENV, verified in TASK 1.1 checklist |
| Community node not visible in n8n UI | `N8N_COMMUNITY_PACKAGES_ENABLED=true` + `N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true` baked in |
| arm64 build slow | GHA cache (`type=gha,mode=max`) speeds up subsequent builds |
| Supabase table mismatch | hooks push to `n8n_execution_logs` — migration SQL matches exactly |
| Image size ~2GB | Normal for Chromium + playwright binaries. `.dockerignore` keeps build context small. |

---

*Generated by Minis for Aldrin | n8n-playwright agent spec v2*
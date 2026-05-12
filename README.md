# n8n-playwright Docker Image

A single self-contained Docker image for n8n with Chromium CDP, pre-installed community Playwright node, and execution hooks for Supabase logging.

## 1. Overview
This image combines **n8n** with **Chromium** (running in Xvfb) and the **n8n-nodes-playwright** community node. It also includes an execution hook to log workflow results directly to a Supabase table.

- **n8n**: Workflow automation tool.
- **Chromium CDP**: Remote debugging enabled on port 9222.
- **Playwright Node**: Pre-installed and ready to use.
- **Execution Hooks**: Automatically logs executions to Supabase.

## 2. Quick Start
1. **Clone** this repository:
   ```bash
   git clone <repo-url>
   cd n8n-playwright
   ```
2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env and fill in your values
   ```
3. **Run Supabase Migration**:
   Execute the contents of `supabase_migration.sql` in your Supabase SQL Editor to create the `n8n_execution_logs` table.
4. **Deploy**:
   ```bash
   docker compose up -d
   ```

## 3. Ports
- `5678`: n8n Web UI
- `9222`: Chrome CDP (Remote Debugging)

## 4. Connect Playwright to CDP
You can connect your Playwright scripts to the browser running inside the container:
- **From host machine**: `ws://localhost:9222`
- **Internal (other containers)**: `ws://n8n-playwright:9222`

## 5. Playwright Community Node
The `n8n-nodes-playwright` package is pre-installed. You can find it in the n8n node picker after the container starts. It is configured to use the internal Chromium instance by default.

## 6. Upgrade n8n
To upgrade the n8n version:
1. Update `N8N_VERSION` in your GitHub repository's **Settings → Variables → Actions**.
2. Re-run the CI/CD workflow.
3. On your server, run:
   ```bash
   docker compose pull && docker compose up -d
   ```

## 7. Execution Hooks
The image includes `execution-hooks.js` which pushes logs to Supabase.
- Ensure `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` are set in your `.env`.
- Ensure the `n8n_execution_logs` table exists (run `supabase_migration.sql`).

## 8. Local Build
To build the image locally:
```bash
docker build --build-arg N8N_VERSION=2.19.5 -t n8n-playwright .
```

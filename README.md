# n8n-playwright Docker Image

A specialized Docker image for n8n that includes a pre-configured Chromium environment for Playwright, automated execution hooks for Supabase, and a robust multi-stage build process.

## 1. Overview
This image is designed for high-reliability web automation within n8n. It bundles:
- **n8n**: The core workflow automation tool.
- **Chromium CDP**: Remote debugging enabled on port `9222` with Xvfb for headless operation.
- **Playwright Community Node**: Pre-installed (`n8n-nodes-playwright`) and pre-configured to use the system Chromium.
- **Execution Hooks**: Automatically pushes workflow execution status and IDs to a Supabase table.
- **Smart Build**: A multi-stage build process that ensures Chromium stability and correct library mapping.

## 2. Prerequisites

### Install Docker & Docker Compose (Ubuntu/Debian)
If you don't have Docker installed yet, run these commands:

```bash
# Update package list
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io

# Install Docker Compose (V2 Plugin)
sudo apt-get install -y docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

## 3. Quick Start
1. **Clone** the repository:
   ```bash
   git clone https://github.com/Kiryuuki/n8n-build
   cd n8n-build
   ```
2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env and fill in your Supabase and n8n credentials
   ```
3. **Run Supabase Migration**:
   Copy the content of `supabase_migration.sql` and run it in your Supabase SQL Editor to create the necessary logging table.
4. **Deploy**:
   ```bash
   docker compose up -d
   ```

## 4. Ports
- `5678`: n8n Web UI
- `9222`: Chrome CDP (Remote Debugging Address)

## 5. Connect Playwright to CDP
You can connect external Playwright scripts or other containers to the browser instance:
- **From Host**: `ws://localhost:9222`
- **Internal Network**: `ws://n8n-playwright:9222`

## 6. Playwright Community Node
The `n8n-nodes-playwright` node is baked into the image. 
- It is located in `/home/node/.n8n/custom`.
- It is automatically "tricked" into using the system Chromium via a symlink strategy, preventing large browser downloads at runtime.

## 7. CI/CD & Upgrades
The repository includes a GitHub Actions workflow (`docker-publish.yml`) that builds and pushes the image to GHCR.

**To upgrade n8n version:**
1. Go to your GitHub Repo **Settings → Variables → Actions**.
2. Update the `N8N_VERSION` variable.
3. Re-run the `Build and Push` workflow.
4. On your production server:
   ```bash
   docker compose pull && docker compose up -d
   ```

## 8. Execution Hooks
The `execution-hooks.js` file is automatically loaded. It logs:
- `execution_id`
- `workflow_name`
- `status` (success/failed)

Ensure your `.env` contains `SUPABASE_URL` and `SUPABASE_SERVICE_KEY`.

## 9. Local Build
If you want to build the image locally with a specific n8n version:
```bash
docker build --build-arg N8N_VERSION=2.19.5 -t n8n-playwright .
```
*(Note: The build uses a multi-stage Alpine process to ensure Chromium compatibility across different base OS variants.)*

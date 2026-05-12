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

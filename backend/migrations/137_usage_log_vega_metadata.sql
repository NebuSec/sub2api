ALTER TABLE usage_logs
  ADD COLUMN IF NOT EXISTS vega_scan_id text,
  ADD COLUMN IF NOT EXISTS vega_project_id text,
  ADD COLUMN IF NOT EXISTS vega_request_id text,
  ADD COLUMN IF NOT EXISTS vega_runner_id text;

CREATE INDEX IF NOT EXISTS usage_logs_vega_scan_id_created_at_idx
  ON usage_logs (vega_scan_id, created_at DESC)
  WHERE vega_scan_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS usage_logs_vega_project_id_created_at_idx
  ON usage_logs (vega_project_id, created_at DESC)
  WHERE vega_project_id IS NOT NULL;

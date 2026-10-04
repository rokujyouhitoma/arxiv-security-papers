-- Migration: baseline (DOWN)
-- Version:   0001
-- Backend:   Compatible with Primary (src.database) and Secondary (sqlite3)
-- Created:   2026-09-23T00:00:00+00:00

-- ============================================================================
-- 3. Cyber Threat Intelligence (CTI) Catalog Tables (Reverse Order)
-- ============================================================================
DROP INDEX IF EXISTS idx_cisa_kev_ransomware;
DROP TABLE IF EXISTS cisa_kev_vulnerabilities;

DROP INDEX IF EXISTS idx_cwe_rel_target;
DROP TABLE IF EXISTS cti_cwe_relationships;

DROP INDEX IF EXISTS idx_cwe_top25;
DROP TABLE IF EXISTS cti_cwes;

DROP INDEX IF EXISTS idx_rel_target;
DROP TABLE IF EXISTS cti_relationships;

DROP TABLE IF EXISTS cti_mitigations;

DROP INDEX IF EXISTS idx_tech_parent;
DROP TABLE IF EXISTS cti_techniques;

DROP TABLE IF EXISTS cti_tactics;

-- ============================================================================
-- 2. Spider Execution Logs Table (Reverse Order)
-- ============================================================================
DROP INDEX IF EXISTS idx_spider_exec_job_id;
DROP TABLE IF EXISTS spider_execution_logs;

-- ============================================================================
-- 1. Analytics Tables (Reverse Order)
-- ============================================================================
DROP TABLE IF EXISTS latest_snapshot;

DROP INDEX IF EXISTS idx_history_epoch;
DROP TABLE IF EXISTS metrics_history;

DROP INDEX IF EXISTS idx_kpis_category;
DROP TABLE IF EXISTS strategic_kpis;

DROP INDEX IF EXISTS idx_threat_category;
DROP TABLE IF EXISTS threat_trends;

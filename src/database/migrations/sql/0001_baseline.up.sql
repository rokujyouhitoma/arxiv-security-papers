-- Migration: baseline (UP)
-- Version:   0001
-- Backend:   Compatible with Primary (src.database) and Secondary (sqlite3)
-- Created:   2026-09-23T00:00:00+00:00

-- ============================================================================
-- 1. Analytics Tables and Indexes
-- ============================================================================
CREATE TABLE IF NOT EXISTS threat_trends (
    name TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    count INTEGER NOT NULL,
    prev_count INTEGER NOT NULL,
    growth_pct REAL NOT NULL,
    sample_ids TEXT,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_threat_category ON threat_trends(category);

CREATE TABLE IF NOT EXISTS strategic_kpis (
    kpi_key TEXT PRIMARY KEY,
    kpi_category TEXT NOT NULL,
    num_value REAL,
    text_value TEXT,
    metadata_json TEXT,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_kpis_category ON strategic_kpis(kpi_category);

CREATE TABLE IF NOT EXISTS metrics_history (
    id INTEGER PRIMARY KEY,
    snapshot_json TEXT NOT NULL,
    collected_at TEXT NOT NULL,
    created_epoch REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_history_epoch ON metrics_history(created_epoch);

CREATE TABLE IF NOT EXISTS latest_snapshot (
    snapshot_key TEXT PRIMARY KEY,
    snapshot_json TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    updated_at_epoch REAL NOT NULL
);

-- ============================================================================
-- 2. Spider Execution Logs Table and Indexes
-- ============================================================================
CREATE TABLE IF NOT EXISTS spider_execution_logs (
    job_id TEXT,
    spider_name TEXT,
    status TEXT,
    started_at TEXT,
    finished_at TEXT,
    duration_seconds REAL,
    item_count INTEGER,
    http_status_counts TEXT,
    error_message TEXT,
    params TEXT
);

CREATE INDEX IF NOT EXISTS idx_spider_exec_job_id ON spider_execution_logs(job_id);

-- ============================================================================
-- 3. Cyber Threat Intelligence (CTI) Catalog Tables and Indexes
-- ============================================================================
CREATE TABLE IF NOT EXISTS cti_tactics (
    tactic_id TEXT PRIMARY KEY,
    shortname TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    external_url TEXT
);

CREATE TABLE IF NOT EXISTS cti_techniques (
    technique_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    is_subtechnique INTEGER DEFAULT 0,
    parent_technique_id TEXT,
    platforms_json TEXT,
    tactics_json TEXT,
    external_url TEXT,
    stix_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_tech_parent ON cti_techniques(parent_technique_id);

CREATE TABLE IF NOT EXISTS cti_mitigations (
    mitigation_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    external_url TEXT,
    stix_id TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS cti_relationships (
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    rel_type TEXT NOT NULL,
    PRIMARY KEY (source_id, target_id, rel_type)
);

CREATE INDEX IF NOT EXISTS idx_rel_target ON cti_relationships(target_id);

CREATE TABLE IF NOT EXISTS cti_cwes (
    cwe_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    abstraction TEXT,
    description TEXT,
    top25_rank INTEGER,
    is_top25 INTEGER DEFAULT 0,
    status TEXT,
    mitigations_json TEXT,
    extended_meta TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_cwe_top25 ON cti_cwes(is_top25);

CREATE TABLE IF NOT EXISTS cti_cwe_relationships (
    source_cwe_id TEXT NOT NULL,
    target_cwe_id TEXT NOT NULL,
    relation_type TEXT NOT NULL,
    PRIMARY KEY (source_cwe_id, target_cwe_id, relation_type)
);

CREATE INDEX IF NOT EXISTS idx_cwe_rel_target ON cti_cwe_relationships(target_cwe_id);

CREATE TABLE IF NOT EXISTS cisa_kev_vulnerabilities (
    cve_id TEXT PRIMARY KEY,
    vendor_project TEXT NOT NULL,
    product TEXT NOT NULL,
    vulnerability_name TEXT NOT NULL,
    date_added TEXT NOT NULL,
    short_description TEXT,
    required_action TEXT,
    due_date TEXT,
    known_ransomware_campaign_use TEXT,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_cisa_kev_ransomware ON cisa_kev_vulnerabilities(known_ransomware_campaign_use);

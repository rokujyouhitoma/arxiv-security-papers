# Issue 158: Implement Structured Audit Trail & Forward-Secure Chained Log

## 1. 概要 (Overview)
`DSN-07` Rev 2.1 に基づき、システム内の全セキュリティ重要イベント（認証成否、RBAC権限違反、SSRF遮断、シークレット漏洩検知、インジェスト超過、レートリミット等）を統一スキーマで記録する構造化監査ログ基盤（`src/security/audit/event_logger.py`）および、ログの改ざん・削除・順序入替を数学的に検知する前方安全ハッシュ連鎖ログ（`src/security/audit/chained_log.py`）を実装する。

## 2. 目的・背景 (Motivation & Background)
- Antigravity IDE およびマルチエージェント運用環境において、誰が・いつ・何に対して・どのようなアクションを実行し・成否がどうであったかの完全なトレーサビリティ（Provenance & Auditability）を保証する。
- 監査ログ自体が悪意ある攻撃者や侵入者によって事後改ざん・行削除されるインシデントを防ぐため、HMAC-SHA256 連鎖ハッシュ構造（Forward-Secure Hash Chaining）を導入し、1バイトの変更や1行の欠落も即座に完全性検証で検出可能にする。
- ログ出力時にシークレットや認証トークンが平文で混入しないよう、自動マスキングフィルターを強制適用する。

## 3. 実装要件 (Requirements)
1. **構造化セキュリティ監査イベント (`src/security/audit/event_logger.py`)**:
   - `SecurityAuditEvent`: `event_id`, `timestamp` (UTC ISO 8601), `event_type` (`AUTH_LOGIN`, `AUTH_FAILURE`, `RBAC_VIOLATION`, `SSRF_BLOCKED`, `SECRET_LEAK_DETECTED`, `INGEST_QUOTA_EXCEEDED`, `RATE_LIMIT_TRIGGERED`), `severity` (`INFO`, `WARNING`, `ERROR`, `CRITICAL`), `actor`, `action`, `target_resource`, `client_ip`, `status` (`SUCCESS`, `FAILURE`, `BLOCKED`), `metadata`
   - シークレット自動マスキング機能付き JSON シリアライザ
   - `SecurityAuditLogger`: イベント記録・検索・バッファリング
2. **前方安全ハッシュ連鎖ログ (`src/security/audit/chained_log.py`)**:
   - `ChainedLogEntry`: `index`, `timestamp`, `payload`, `prev_hash`, `current_hash`
   - `current_hash` = `HMAC-SHA256(chain_key, f"{index}:{prev_hash}:{canonical_json(payload)}")`
   - Genesis ブロック (`index=0`, `prev_hash="0"*64`) からの厳格連鎖
   - `verify_chain_integrity(entries: List[ChainedLogEntry], chain_key: bytes) -> Tuple[bool, Optional[int], Optional[str]]`
3. **品質・制約要件**:
   - Python標準ライブラリ (`hashlib`, `hmac`, `json`, `time`, `datetime`, `uuid`, `typing`) のみ使用。
   - Xenon 循環的複雑度 $\le 5$ (Rank A)。
   - Mypy `--strict` 準拠。

## 4. 対象ファイル (Target Files)
- `src/security/audit/__init__.py`: 新規作成
- `src/security/audit/event_logger.py`: 新規作成
- `src/security/audit/chained_log.py`: 新規作成
- `src/security/__init__.py`: エクスポート追加
- `tests/security/test_audit_chain.py`: 単体テスト新規作成

## 5. 完了定義 (Definition of Done)
- [x] `SecurityAuditLogger` が機密情報を自動マスキングしながら統一スキーマでイベントを記録できること
- [x] `ChainedLogEntry` が HMAC-SHA256 による連鎖ハッシュを生成し、改ざん・削除・順序変更を 100% 検知できること
- [x] 単体テスト `tests/security/test_audit_chain.py` が 100% PASS すること
- [x] `make check_format` および `make static_analysis` (xenon, flake8, mypy --strict) が PASS すること

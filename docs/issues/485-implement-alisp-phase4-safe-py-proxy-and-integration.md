---
ID: 485
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ALisp Phase 4: Python FFI 物理的完全性 (SafePyProxy)・リソース制限・監査テレメトリ統合の実装 (ID: 485)

## 1. 概要 / Summary
[DSN-32 第12.5節](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) に基づき、ALisp のセキュリティ完全性および運用統合フェーズ（Phase 4）を実装する。
Python オブジェクトが Lisp 環境に渡された際のリフレクション・メタオブジェクト探索脱獄を物理遮断する **`SafePyProxy`**（Dunder 属性アクセス常時拒絶）、`resource.setrlimit` による物理メモリクォータガード、OS タイマーによる壁時計時間（Wall-Clock Hard Timeout）フェイルセーフ、JSON Lines 構造化監査ログ（`alisp_events.jsonl`）、および W3C TraceContext 連動テレメトリを実装し、全系結合テスト・E2E 検証を完了する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 3.4 節, 第 8 章, 第 11 章, 第 12.5 節)
  - [DSN-07: Security Guard & RBAC](../../docs/designs/DSN-07-security_guard_and_rbac.md)
  - [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 4 節 Python Interop)
- **対象サブシステム**:
  - `alisp/caps/safe_proxy.py`
  - `alisp/telemetry/`
  - `manage.py`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [alisp/caps/safe_proxy.py](../../alisp/caps/safe_proxy.py) (`SafePyProxy` クラス, Dunder 属性常時拒絶)
- [ ] [alisp/metering.py](../../alisp/metering.py) (`SIGALRM` 壁時計時間タイマー, `resource.setrlimit` メモリ制限)
- [ ] [alisp/telemetry/__init__.py](../../alisp/telemetry/__init__.py) (テレメトリ基盤初期化)
- [ ] [alisp/telemetry/audit.py](../../alisp/telemetry/audit.py) (JSON Lines 監査ログエクスポータ, W3C TraceContext)
- [ ] [manage.py](../../manage.py) (ALisp CLI 実行サブコマンド統合)
- [ ] [tests/alisp/test_phase4_safe_proxy_and_telemetry.py](../../tests/alisp/test_phase4_safe_proxy_and_telemetry.py) (脱獄テスト 100 パターン, E2E テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/485-implement-alisp-phase4-safe-py-proxy-and-integration`

1. **`SafePyProxy` の実装 (`alisp/caps/safe_proxy.py`)**:
   - Python オブジェクトを透過的にラップするプロキシクラス。
   - `__class__`, `__globals__`, `__subclasses__`, `__mro__`, `__code__`, `__builtins__` 等のメタ属性アクセス要求に対して常時 `AccessDeniedException` を送出。
2. **物理リソースクォータ ＆ ハードタイムアウトの実装**:
   - `resource.setrlimit(resource.RLIMIT_AS, ...)` によるホストプロセス仮想メモリ上限（例: 512MB）の設定。
   - `SIGALRM` / バックグラウンドスレッドによる実時間ハードタイムアウト（デフォルト 5.0 秒）の実装。
3. **構造化監査テレメトリ (`alisp/telemetry/audit.py`)**:
   - イベント（契約違反、Fuel 枯渇、権限拒絶、パッチ適用）を `outputs/database/alisp_events.jsonl` へ JSON Lines 追記。
   - W3C TraceContext（Trace ID）を自動抽出・付与。
4. **全系結合テスト ＆ CLI 統合**:
   - `manage.py alisp run <file.alisp>` コマンドの提供。
   - 悪意ある脱獄コード 100 パターンの自動テスト全件遮断検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `SafePyProxy` を介したメタオブジェクト探索脱獄（`().__class__.__base__...` 等）100 パターンが全件例外なく確実に拒絶されること。
- [ ] 巨大メモリ確保コード（例: `'x' * 10**10`）が安全にメモリクォータ制限で停止すること。
- [ ] `alisp_events.jsonl` に正確なタイムスタンプ、Trace ID、イベント種別が構造化記録されること。
- [ ] `make format`, `make static_analysis`, `make test` が 100% PASS すること。

---
ID: 485
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ALisp Phase 4: Python FFI 物理的完全性 (SafePyProxy)・リソース制限・監査テレメトリ統合の実装 (ID: 485)

## 1. 概要 / Summary
[DSN-32 第12.5節](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) に基づき、ALisp のセキュリティ完全性および運用統合フェーズ（Phase 4）を実装する。
Python オブジェクトが Lisp 環境に渡された際のリフレクション・メタオブジェクト探索脱獄を物理遮断する **`SafePyProxy`**（Dunder 属性アクセス常時拒絶）、`resource.setrlimit` による物理メモリクォータガード、OS タイマー（`SIGALRM` / Real-Time Timer）による壁時計時間（Wall-Clock Hard Timeout）フェイルセーフ、JSON Lines 構造化監査ログ（`alisp_events.jsonl`）、および W3C TraceContext 連動テレメトリを実装し、全系結合テスト・E2E 検証を完了する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 3.4 節, 第 8 章, 第 11 章, 第 12.5 節, 第 13 章)
  - [DSN-07: Security Guard & RBAC](../../docs/designs/DSN-07-security_guard_and_rbac.md)
  - [DSN-31: ILISP R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 4 節 Python Interop)
- **対象サブシステム**:
  - `alisp/caps/safe_proxy.py` (新規作成)
  - `alisp/caps/__init__.py` (SafePyProxy エクスポート・連携)
  - `alisp/metering.py` (SIGALRM 壁時計時間タイマー, resource.setrlimit メモリ制限)
  - `alisp/telemetry/__init__.py` (新規作成: テレメトリ基盤)
  - `alisp/telemetry/audit.py` (新規作成: JSON Lines 監査ログ, W3C TraceContext)
  - `alisp/core.py` (SafePyProxy, テレメトリ, リソースガード統合)
  - `alisp/__init__.py` (公開シンボルエクスポート)
  - `manage.py` (ALisp CLI 実行サブコマンド統合)
  - `tests/alisp/test_phase4_safe_proxy_and_telemetry.py` (新規作成: 脱獄テスト 100 パターン, E2E 検証)

---

## 3. 脅威モデルとセキュリティ要件 (Threat Model & Security Mitigations)
1. **メタオブジェクト探索脱獄 (CWE-200 / CWE-94)**:
   - 脅威: Lisp 環境から Python オブジェクトの `__class__`, `__globals__`, `__subclasses__`, `__mro__`, `__code__`, `__builtins__` などを探索し、`os.system` やファイル I/O を実行してサンドボックスを脱獄する。
   - 対策: `SafePyProxy` により、`__*__` 形式の属性名（および安全と明示された特殊メソッド以外、あるいはメタオブジェクト探索に繋がる全属性）へのアクセスを例外なく即時拒絶（`AccessDeniedException`）。
2. **物理リソース枯渇 DoS (CWE-400 / CWE-770)**:
   - 脅威: `'x' * (10**10)` や巨大リストの確保、または C-level/Python ビルトインによるブロッキング無限ループ。
   - 対策: `resource.setrlimit(resource.RLIMIT_AS, ...)` によるホストプロセス仮想メモリクォータ制限、および OS シグナル (`SIGALRM`) / バックグラウンドタイマーによる壁時計実時間ハードタイムアウト（例: 5.0秒）による即時中断。
3. **監査証跡の改ざん・未記録 (CWE-778)**:
   - 対策: `outputs/database/alisp_events.jsonl` に W3C TraceContext (`traceparent`, `trace_id`, `span_id`) を紐付け、評価開始・成功・燃料枯渇・タイムアウト・権限拒絶・パッチ適用の全イベントを不可逆構造化追記。

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/485-implement-alisp-phase4-safe-py-proxy-and-integration`

1. **`SafePyProxy` の実装 (`alisp/caps/safe_proxy.py`)**:
   - Python オブジェクトを安全にラップする透過的プロキシクラス `SafePyProxy` を作成。
   - 属性アクセス (`__getattr__`, `__setattr__`, `__delattr__`) において、`__class__`, `__globals__`, `__subclasses__`, `__mro__`, `__code__`, `__builtins__`, `__dict__`, `__module__`, `__qualname__`, `__bases__`, `__base__`, `__init__`, `__new__`, `__reduce__`, `__reduce_ex__` などのメタ属性アクセス要求を常時検知し、`AccessDeniedException` を送出。
   - 一般属性アクセス、メソッド呼び出し、インデックス (`__getitem__`, `__setitem__`)、反復 (`__iter__`)、長さ (`__len__`)、文字列表現 (`__str__`, `__repr__`) を安全に委譲。
   - 戻り値が Python オブジェクトの場合は再帰的に `SafePyProxy` で安全にラップ。
   - `alisp/caps/__init__.py` から `SafePyProxy`, `wrap_safe_proxy`, `unwrap_safe_proxy`, `is_safe_proxy` をエクスポート。
   - `alisp/core.py` において、`ilisp` の Python Interop プリミティブ (`py-import`, `py-call`, `py-get`, `py-set!`, `.` 等) に `SafePyProxy` 統合を適用。危険な組み込みモジュール (`os`, `subprocess`, `sys`, `importlib` 等) の直接インポートを Capability 境界で制御。

2. **物理リソースクォータ ＆ ハードタイムアウトの実装 (`alisp/metering.py`)**:
   - `resource.setrlimit(resource.RLIMIT_AS, ...)` を用いたメモリクォータ管理コンテキストマネージャ `with_memory_quota(max_bytes)`.
   - `signal.setitimer(signal.ITIMER_REAL, ...)` / `signal.SIGALRM` を用いた壁時計時間ハードタイマー `with_wall_clock_timeout(seconds)`.
   - メインスレッド外や非 UNIX 環境向けのタイマースレッドフォールバック設計。

3. **構造化監査テレメトリ (`alisp/telemetry/`)**:
   - `alisp/telemetry/__init__.py` および `alisp/telemetry/audit.py` の新規作成。
   - W3C TraceContext（Trace ID 32文字 hex, Span ID 16文字 hex）生成・管理。
   - `AuditLogger` クラスおよびコンテキスト変数を実装。
   - イベント（`EVAL_START`, `EVAL_SUCCESS`, `CONTRACT_VIOLATION`, `FUEL_EXHAUSTED`, `TIMEOUT`, `ACCESS_DENIED`, `PATCH_APPLIED`, `MEMORY_LIMIT_EXCEEDED`）を `outputs/database/alisp_events.jsonl` へ JSON Lines 追記。

4. **全系結合テスト ＆ CLI 統合**:
   - `manage.py` に `alisp` コマンドグループ（`manage.py alisp run <file.alisp>` 等）を追加。
   - `tests/alisp/test_phase4_safe_proxy_and_telemetry.py` を作成:
     - メタオブジェクト探索脱獄 100 パターン（様々な Python 内部属性探索・バイパス試行）の完全遮断検証。
     - 巨大メモリ確保コードのメモリクォータ遮断検証。
     - 壁時計時間ハードタイムアウト検証。
     - JSON Lines 監査ログ ＆ W3C TraceContext 出力検証。
     - CLI 実行の E2E 動作検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `SafePyProxy` を介したメタオブジェクト探索脱獄（`().__class__.__base__...` 等）100 パターンが全件例外なく確実に拒絶されること。
- [x] 巨大メモリ確保コード（例: `'x' * 10**10`）が安全にメモリクォータ制限で停止すること。
- [x] 壁時計時間ハードタイムアウト（`SIGALRM` / Real-Time Timer）が正しく動作し、物理的な無限ループを遮断できること。
- [x] `outputs/database/alisp_events.jsonl` に正確な ISO 8601 タイムスタンプ、Trace ID、イベント種別が構造化記録されること。
- [x] `manage.py alisp run <file>` コマンドが正常に動作すること。
- [x] `make format`, `make static_analysis`, `make test` が 100% PASS すること。

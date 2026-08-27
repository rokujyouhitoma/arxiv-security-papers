# [FEAT] ストリーミング型 DAG & バックプレッシャー制御パイプライン (Streaming DAG & Reactive Backpressure Engine) の実装 (ID: 088)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 088 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | Systems Architect (SA) / Embedded Systems Specialist (IoT) |
| **対象ブランチ** | `feat/088-streaming-dag-and-backpressure-pipeline` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/workflow/`）に、大量の学術論文・セキュリティフィード（数千〜数万件）をメモリ上限（Bounded Memory）内で高スループット処理可能にする「ストリーミング型 DAG & 反応型バックプレッシャー制御エンジン（`StreamingDAG`）」を実装する。下流の処理遅延（PDF解析、ベクトルインデックス構築、DB書き込み）を検知して上流のフェッチ速度を自律スロットリングし、OOM（Out of Memory）を完全に防止する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/workflow/streaming_dag.py` (新規: StreamChunk, BufferPolicy, StreamingTaskNode, StreamingDAG)
- `src/orchestrator/workflow/__init__.py` (ストリーミングDAGシンボルのエクスポート)
- `src/orchestrator/engine.py` (ストリーミング実行モード `stream_cycle` の追加)
- `src/orchestrator/cli.py` (CLI フラグ `--streaming`, `--chunk-size` の追加)
- `tests/orchestrator/test_streaming_dag.py` (新規: 単体 & 統合テスト)
- `docs/issues/README.md` (Issue 台帳更新)
- `docs/designs/DSN-11-intelligence_orchestration_engine.md` (設計書更新)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `StreamChunk`（チャンクデータ、シーケンス番号、EOSフラグ、メタデータ）。
  - `BufferPolicy` Enum（`BLOCK`, `DROP_OLDEST`, `DRAIN`）。
  - `StreamingTaskNode`（入力有界キュー、変換トランスフォーマー、バックプレッシャーステータス）。
  - `StreamingDAG`（ノード接続、トポロジカル実行、ストリーミングデータパイプライン駆動）。
  - 下流バッファ使用率 $> 0.80$ で上流を自律スロットリングするバックプレッシャー機構。
  - ストリーミング実行統計テレメトリ（総アイテム数、スループット、最大バッファ占有率、スロットル発生回数）。
- **非機能・セキュリティ要件**:
  - ゼロ外部依存（Python標準ライブラリのみ）。
  - メモリ上限の厳格な制限（有界キューによる OOM 防止）。
  - 型安全性（`mypy --strict` 0 エラー）および xenon Grade A/B 適合。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/workflow/streaming_dag.py`**:
   - StreamChunk, BufferPolicy, StreamingTaskNode, StreamingDAG を実装。
2. **`src/orchestrator/engine.py`**:
   - `UniversalIntelligenceOrchestrator.stream_cycle()` を実装。
3. **`src/orchestrator/cli.py`**:
   - `cycle` コマンドに `--streaming`, `--chunk-size` を追加。
4. **`tests/orchestrator/test_streaming_dag.py`**:
   - チャンクストリーミング、バックプレッシャー、有界メモリ、DAG実行のテストスイートを作成。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] チャンク単位のストリーミング処理と有界バッファによるバックプレッシャーが正常に動作すること。
- [x] 下流遅延時の自動スロットリングおよびテレメトリ収集が機能すること。
- [x] `tests/orchestrator/test_streaming_dag.py` を含む全テストが 100% PASS すること。
- [x] `make check` (mypy strict, xenon, flake8, black) をクリアすること。

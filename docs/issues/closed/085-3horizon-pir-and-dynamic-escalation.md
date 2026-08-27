# [FEAT] 3-Horizon (戦術・運用・戦略) 多層 PIR 管理および動的エスカレーション基盤の実装 (ID: 085)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 085 |
| **種別** | Feature |
| **優先度** | High |
| **ステータス** | Closed (Resolved) |
| **起票日** | 2026-08-27 |
| **完了日** | 2026-08-27 |
| **担当ロール** | IT Strategist (ST) / Systems Architect (SA) |
| **対象ブランチ** | `feat/085-3horizon-pir-and-dynamic-escalation` |

---

## 1. 概要 / Summary
自律型インテリジェンス・オーケストレーター（`src/orchestrator/pir/`）における PIR（Priority Intelligence Requirements: 優先インテリジェンス要件）管理モデルを高度化し、3 つの時間軸（Tactical: 即時戦術, Operational: 中期運用, Strategic: 長期戦略）を分離・連携管理する「3-Horizon PIR アーキテクチャ」を実装する。また、急上昇脅威（Surge Velocity）や深刻なナレッジギャップ（Knowledge Gap）を検知した際に、要件の優先度を自律的に引き上げる「動的エスカレーション・トリガーループ」を導入する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/orchestrator/pir/models.py` (PIRHorizon 列挙型, PIRRequirement 拡張, HorizonFilter)
- `src/orchestrator/pir/manager.py` (3-Horizon 対応, 重み配分, 動的エスカレーションエンジン)
- `src/orchestrator/contracts.py` (IntelligenceDirective への Horizon メタデータ統合)
- `tests/orchestrator/test_pir_manager.py` (3-Horizon 単体テスト & エスカレーション検証)
- `docs/issues/README.md` (Issue 台帳更新)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - `PIRHorizon` Enum（`TACTICAL`, `OPERATIONAL`, `STRATEGIC`）の定義。
  - `PIRRequirement` に `horizon: PIRHorizon`, `escalation_level: int`, `escalated_at: Optional[str]` を追加。
  - `PIRManager.escalate_requirement(req_id, reason, target_horizon)` による要件の自律昇格。
  - `adapt_queries_from_telemetry` において、ギャップスコアや急上昇キーワードに応じて自動エスカレーションを発火。
  - Horizon 別のフィルタリングおよび時間軸別 Directive 生成機能の提供。
- **非機能・セキュリティ要件**:
  - 無限エスカレーション防止（最大エスカレーションレベルの上限設定）。
  - 型安全性（`mypy --strict` 0 エラー）およびゼロ外部依存（標準ライブラリのみ）の厳格な維持。

---

## 4. 実装方針 / Implementation Plan
1. **`src/orchestrator/pir/models.py`**:
   - `PIRHorizon` Enum を定義し、`PIRRequirement` に時間軸・エスカレーション管理フィールドを追加。
2. **`src/orchestrator/pir/manager.py`**:
   - `escalate_requirement`, `get_requirements_by_horizon`, `evaluate_escalation_triggers` を実装。
   - `adapt_queries_from_telemetry` での急上昇・ナレッジギャップ検知とエスカレーションの連動。
3. **`tests/orchestrator/test_pir_manager.py`**:
   - 3-Horizon 登録・フィルタリング・自動エスカレーションのテストスイートを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `PIRHorizon` (TACTICAL / OPERATIONAL / STRATEGIC) の3階層管理が正常に機能すること。
- [x] ナレッジギャップおよび急上昇検知時に、PIR 要件が自律的にエスカレーション昇格されること。
- [x] `tests/orchestrator/` の全テストが 100% PASS すること。
- [x] `make check` (mypy strict 0エラー, xenon Grade A/B, black/flake8) をクリアすること。

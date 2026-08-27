# [FEAT] 5 階層エグゼクティブサマリーにおける急上昇キーワード（Surge Keywords）時系列クラスタリンググラフおよび防御コード相互リンクの実装 (ID: 084)

| 項目 | 内容 |
| :--- | :--- |
| **ID** | 084 |
| **種別** | Feature |
| **優先度** | Medium |
| **ステータス** | Open (In Progress) |
| **起票日** | 2026-08-27 |
| **担当ロール** | UI/UX Designer (UIUX) / IT Strategist (ST) |
| **対象ブランチ** | `feat/084-dynamic-surge-keyword-clustering-and-okf-crosslinks` |

---

## 1. 概要 / Summary
5 階層エグゼクティブサマリー（`03_monthly`, `04_quarterly`, `05_annual`）において、直近の論文群から急上昇しているセキュリティキーワード（Surge Keywords / Velocity Delta）を自動抽出し、動的 Mermaid クラスタリングチャートを挿入する。さらに、各論文の OKF ドキュメントと `src/security/` の防御実装・MCP ツールへの相互相対リンクを自動生成する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- `src/pipeline/reporter/summary_generator.py` (5階層サマリー生成ロジック)
- `src/pipeline/reporter/diagram_generator.py` (Mermaid チャート生成)
- `src/search/vector/hybrid.py` (キーワード頻度・TF-IDF / 速度計算)
- `tests/pipeline/test_reporter.py` (サマリー生成単体テスト)

---

## 3. 要件定義と脅威モデル / Requirements & Threat Model
- **機能要件**:
  - 月次・四半期サマリーの冒頭に `## 📈 急上昇セキュリティ技術・脅威トレンド` セクションを追加。
  - 前期間比で頻度が増加したキーワードトップ 5（例: `SafeTensors`, `ML-KEM`, `Slopsquatting`）を算出し、Mermaid マインドマップおよびテーブル形式で表示。
  - 完全日本語表記・マークダウン表形式規約の 100% 遵守。
- **非機能要件**:
  - サマリー生成時間のオーバーヘッドを 500ms 以内に抑制。
  - 相対パスリンクガバナンス（絶対パス 0 件）の完全維持。

---

## 4. 実装方針 / Implementation Plan
1. **`src/pipeline/reporter/diagram_generator.py`**:
   - `generate_surge_trend_mermaid(papers)` を実装。
2. **`src/pipeline/reporter/summary_generator.py`**:
   - 月次・四半期・通期サマリー生成テンプレートにトレンド分析セクションを統合。
3. **`tests/pipeline/test_reporter.py`**:
   - トレンド解析付きサマリー生成テストを追加。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 月次・四半期サマリーに急上昇キーワードの Mermaid チャートおよび解説が自動挿入されること。
- [ ] 100% 日本語規約および相対パス規約が完全に維持されていること。
- [ ] `tests/pipeline/` の全テストが PASS すること。
- [ ] `make check` をクリアすること。

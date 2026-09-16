---
ID: 313
種別: Feature / Enhancement
優先度: High
ステータス: Closed
---

# [FEAT] 動的垂直バンド分割 (Vertical Band Segmentation) による 1段組・2段組混在学術論文レイアウト読書順序復元 (ID: 313)

## 1. 概要 / Summary
学術論文（特に arXiv, IEEE, ACM, USENIX 形式）では、第1ページにおいて「タイトル・著者・アブストラクト（1段組・中央揃え）」が上部に配置され、その直下から「本文（2段組）」に切り替わる。さらに本文中にもページ全幅を占める図（Figure）や表（Table）、脚注（Footnote）が挿入される。
従来の `src/pdf_engine/layout.py` は、ページ全体を単一の境界（`page_height * 0.5`）でヘッダー・本文・フッターに決め打ち分割していたため、アブストラクトの途中で本文が混ざる、あるいは本文左右カラムの読書順序（Reading Order）が崩壊していた。

本タスクでは、行の空間座標から全幅行（Span lines）と左右カラム行（Column lines）のクラスタを動的に検出し、ページを複数の垂直バンド（Vertical Bands: 1カラムブロックと2カラムブロックの連鎖）に分割する **Dynamic Vertical Band Segmentation Engine** を実装した。さらに、タイトルや概要などの全幅グリフをガター検出の対象外とするフィルタリングを導入し、中央ガターの検出精度を大幅に向上させた。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: ISO 32000-1 Clause 14.7 (Logical Structure & Reading Order)
- 関連 Issue: [#312](312-pdf-font-widths-and-space-inference.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/pdf_engine/layout.py` (`SpatialLayoutEngine` に動的バンド分割、ヘッダー/フッター自動検出、および2段組ブロック内整列を実装)
- [x] `tests/pdf_engine/test_layout.py` (混在レイアウトの互換性維持)
- [x] `tests/pdf_engine/test_dynamic_bands.py` (新規ユニットテスト PASS)
- [x] `src/pdf_engine/benchmark.py` による定量的精度測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/313-pdf-dynamic-band-segmentation-two-column`

1. **行の列スパン分類（Column Span Classification）**:
   - 行が中央ガター `gutter_x` を跨いでいるか（`line.min_x < gutter_x - 20 and line.max_x > gutter_x + 20`）を判定。
   - 跨いでいる場合は `FULL`、左側は `LEFT`、右側は `RIGHT`。
2. **動的垂直バンドの形成（Band Formation）**:
   - Y座標降順（上から下）に走査し、`FULL` 行の連続を 1カラムバンド、`LEFT` / `RIGHT` 行の連続を 2カラムバンドとしてグループ化。
   - 2カラムバンドでは、左カラム行（Y降順）を出力した後に右カラム行（Y降順）を出力。
3. **中央ガター検出の全幅要素除外**:
   - `_is_column_bound` により、タイトル・アブストラクト等の全幅グリフがガターヒストグラムを埋めてしまう問題を解消。
4. **品質検証**:
   - `xenon Grade A` ($CC \le 4$)、`mypy --strict`。
   - ユニットテスト全件 PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] タイトル・アブストラクト（1段組）と本文（2段組）が混在する論文で、アブストラクトが本文に先立って正しく抽出されること。
- [x] 2カラムブロック内において、左カラムが完全に読み終わってから右カラムが読まれること。
- [x] `tests/pdf_engine/` 全テストが 100% PASS すること。
- [x] 実 arXiv 論文ベンチマークで定量的に評価を実施すること。

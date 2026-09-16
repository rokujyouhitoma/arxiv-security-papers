---
ID: 312
種別: Feature / Enhancement
優先度: High
ステータス: Closed
---

# [FEAT] PDF フォント /Widths 配列解析と文字間スペース・カーニング精密推定の実装 (ID: 312)

## 1. 概要 / Summary
現在の `pdf_engine` のテキスト抽出処理（`src/pdf_engine/interpreter.py`）では、各文字の描画幅を `font_size * 0.5`（固定 0.5em）で一律概算していた。
プロポーショナルフォント（Times, Computer Modern, Arial 等）では文字ごとに幅が大きく異なるため、固定幅近似によって文字の終端 X 座標が累積的にずれ、`src/pdf_engine/layout.py` の単語間スペース判定（`gap >= space_threshold`）において「単語内に誤ったスペースが挿入される（例: `secu rity`）」あるいは「単語間のスペースが欠落して単語が結合する（例: `inthepaper`）」という精度劣化が発生していた。

本タスクでは、ISO 32000-1 Clause 9.6-9.7 に準拠し、フォント辞書内の `/FirstChar`, `/LastChar`, `/Widths` 配列（および `/FontDescriptor` の `/MissingWidth`）を解析して各グリフの正確な前進幅（Advance Width）を取得する。さらに `TJ` オペレータ内のカーニング補正値を忠実に加算し、文字および単語のバウンディングボックス計算精度を極限まで高めた。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: ISO 32000-1:2008 (Clause 9.6, 9.7 Font Dictionaries & Glyph Widths)
- 関連 Issue: [#310](310-pure-peg-pdf-tounicode-cmap-parser.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/pdf_engine/font.py` (`FontDecoder` に `/Widths`, `/FirstChar`, `/LastChar`, `/MissingWidth` 解析と `get_char_width` / `get_text_width` を実装)
- [x] `src/pdf_engine/interpreter.py` (`_render_text_bytes` において各文字の実際の幅に基づく `GlyphBox` 生成と `tm[4]` 前進量の精密化)
- [x] `src/pdf_engine/layout.py` (`_should_insert_space` のギャップ判定精度のチューニング)
- [x] `tests/pdf_engine/test_font_widths.py` (新規ユニットテスト 6件 PASS)
- [x] 既存 `tests/pdf_engine/` の全テスト（67件） 100% 互換性維持

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/312-pdf-font-widths-and-space-inference`

1. **`FontDecoder` における幅情報の抽出**:
   - `font_dict` から `/FirstChar` (int), `/LastChar` (int), `/Widths` (List[int/float]) を抽出。
   - `/FontDescriptor` 辞書が存在する場合は `/MissingWidth`（デフォルト 250 / 1000）を取得。
   - `get_char_width` / `get_text_width`: フォント幅配列、CID 2byte フォント、Courier 固定幅フォールバックを実装。
2. **`TextInterpreter` の `_render_text_bytes` 精密化**:
   - デコーダーから得られる正確な幅と `word_spacing`, `char_spacing` を加算。
3. **`layout.py` のスペース閾値最適化**:
   - `space_threshold = max(prev_g.font_size, cur_g.font_size) * 0.18` に調整。
4. **品質検証**:
   - `xenon Grade A` ($CC \le 4$)、`mypy --strict`。
   - `tests/pdf_engine/` 全テスト PASS。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `FontDecoder` が `/FirstChar`, `/LastChar`, `/Widths` を正しく読み込み、グリフ前進幅を正確に計算すること。
- [x] 幅情報のないフォントや不正なフォント辞書に対しても安全にフォールバックすること（フェイルセーフ）。
- [x] プロポーショナルフォントでのテキスト抽出において、単語間スペースが正確に復元されること。
- [x] `tests/pdf_engine/` 全テストが 100% PASS すること。
- [x] `make format`, `mypy --strict`, `xenon`（Grade A）を 100% PASS すること。

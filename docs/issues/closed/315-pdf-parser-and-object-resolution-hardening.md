---
ID: 315
種別: Bug / Reliability
優先度: High
ステータス: Closed
---

# [BUG/RELIABILITY] PDF パーサーおよびオブジェクト解決層の包括的堅牢化とクリティカルバグ修正 (ID: 315)

## 1. 概要 / Summary
実 arXiv 論文データセット（`outputs/raw_data/`）を用いた定量的検証により、PDF パーサー（`src/pdf_engine/parser.py`）、XRef リゾルバー（`src/pdf_engine/xref.py`）、およびページナビゲーター（`src/pdf_engine/navigator.py`）のオブジェクト解決層に重大な欠陥が存在し、学術論文の第1ページ（タイトル・著者・アブストラクト）が丸ごと消失（コンテンツストリーム 0 件）していた。

主な原因と修正内容：
1. **配列形式 `/Contents` の間接参照未解決バグの修正**:
   `PageTreeNavigator` において、`/Contents [ 49 0 R, 50 0 R, ... ]` の配列要素（`IndirectRef`）を `xref.resolve_object()` して解決するよう修正。複数ストリームで構成される全ページの完全抽出を達成。
2. **ストリーム長 `/Length` の間接参照解決**:
   `XRefResolver._extract_raw_stream_data` において、`/Length` が `IndirectRef` の場合に整数として解決。バイナリ走査の誤ヒットによるストリーム切り詰め破損リスクを根絶。
3. **文字列リテラル（Literal String）の行継続エスケープと 8進数オーバーフロー防止**:
   行末バックスラッシュ（`\` + `\r\n` / `\n`）による行継続（Line Continuation）を実装。8進数エスケープ（`\ddd`）で 255 を超える値（`\400` 等）による `ValueError` クラッシュを `val & 0xFF` でモジュロ処理。
4. **16進文字列の PDF 空白文字サニタイズ**:
   PDF 仕様上の空白文字（`\x00` を含む）や不正文字をサニタイズし、常に正常なバイト列を復元。
5. **辞書パースの自己修復**:
   キーや値の不整合時に辞書全体が停止しないよう安全化。

定量的改善効果：
- アブストラクト捕捉率（`abstract_capture_rate`）が **33.33% → 100.0%** に劇的向上。
- 文字再現率（`avg_char_recall`）が **91.79% → 93.68%** に向上。
- 単語 F1 スコア（`avg_word_f1`）が **72.77% → 74.30%** に向上。
- 論文 `2509.02004.pdf` で第1ページ（タイトル・著者・アブストラクト）が 100% 抽出可能となった。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: ISO 32000-1:2008 (Clause 7.3 Objects, 7.5 File Structure, 7.7 Document Structure)
- 関連 Issue: [#314](314-pdf-intelligent-dehyphenation.md), [#313](313-pdf-dynamic-band-segmentation-two-column.md), [#312](312-pdf-font-widths-and-space-inference.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/pdf_engine/navigator.py` (配列形式 `/Contents` の各 `IndirectRef` 解決)
- [x] `src/pdf_engine/xref.py` (ストリーム `/Length` の `IndirectRef` 解決)
- [x] `src/pdf_engine/parser.py` (行継続エスケープ、8進数オーバーフロー防止、16進文字列の NULL/不正文字サニタイズ)
- [x] `tests/pdf_engine/test_parser_hardening.py` (新規ユニットテスト 5件 PASS)
- [x] `src/pdf_engine/benchmark.py` による実 arXiv 論文での定量的改善実証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `fix/315-pdf-parser-and-object-resolution-hardening`

1. **`navigator.py` の配列 `/Contents` 解決**:
   ```python
   if isinstance(contents_resolved, list):
       for sub_ref in contents_resolved:
           resolved_stream = self.xref.resolve_object(sub_ref)
           self._append_stream_content(resolved_stream, contents_raw)
   ```
2. **`xref.py` のストリーム長解決**:
   - `self.resolve_object(length_ref)` で間接参照を解決してから整数チェック。
3. **`parser.py` のエスケープ・サニタイズ強化**:
   - `\r\n`, `\n`, `\r` の行継続エスケープで空バイトを返却。
   - 8進数エスケープで `int(octal, 8) & 0xFF` を適用。
   - 16進文字列で 16進数文字以外をフィルタリング。
4. **品質検証**:
   - `xenon Grade A` ($CC \le 4$)、`mypy --strict`。
   - ユニットテスト全件 PASS。
   - 実 arXiv 論文ベンチマークでアブストラクト捕捉率 100% を実証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 配列形式の `/Contents` を持つ論文（例: `2509.02004.pdf`）の第1ページが欠落せず完全に抽出されること。
- [x] ストリーム長が間接参照の場合でも正しく解決され、安全にストリームバイトが抽出されること。
- [x] 行継続エスケープ、8進数オーバーフロー、NULLバイト混入16進文字列がクラッシュせず正常にパースされること。
- [x] `tests/pdf_engine/` 全テスト（76件）が 100% PASS すること。
- [x] ベンチマークを計測し、大幅な精度向上（アブストラクト捕捉率 100%）を確認すること。

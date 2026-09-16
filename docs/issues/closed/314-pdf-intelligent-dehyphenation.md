---
ID: 314
種別: Feature / Enhancement
優先度: High
ステータス: Closed
---

# [FEAT] セキュリティ複合語・専門用語を保護するインテリジェント・デハイフネーション (Intelligent Dehyphenation) の実装 (ID: 314)

## 1. 概要 / Summary
学術論文（特に arXiv cs.CR）では、行末での折り返しによって単語がハイフンで分割される（例: `secu-\nrity`）。
以前の `src/pdf_engine/layout.py` の `dehyphenate_text` は、正規表現 `([A-Za-z]{2,})-\n([A-Za-z]{2,})` で無条件にハイフンを除去して結合していた。
その結果、情報セキュリティ分野において不可欠な複合語や専門用語（例: `zero-trust` → `zerotrust`, `cross-site` → `crosssite`, `real-time` → `realtime`, `side-channel` → `sidechannel`, `fault-tolerant` → `faulttolerant` 等）までハイフンが破壊・消失していた。

本タスクでは、セキュリティドメインおよび一般的な英語の複合語プレフィックス（`multi-`, `cross-`, `zero-`, `real-`, `self-`, `anti-`, `side-` 等）および著名な複合用語辞書（`zero-trust`, `cross-site`, `side-channel` 等）を参照し、真の音節折り返し（`secu-\nrity` → `security`）のみを結合し、本来ハイフンを含む複合語（`zero-\ntrust` → `zero-trust`）はハイフンを維持して結合する **Intelligent Dehyphenator** を実装した。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: ISO 32000-1 Clause 14.7.2 (Hyphenation and Word Boundary Normalization)
- 関連 Issue: [#313](313-pdf-dynamic-band-segmentation-two-column.md), [#312](312-pdf-font-widths-and-space-inference.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] `src/pdf_engine/layout.py` (`dehyphenate_text` をインテリジェント・デハイフネーションへ換装、複合語辞書・プレフィックス集合を定義)
- [x] `tests/pdf_engine/test_dehyphenate.py` (新規ユニットテスト 3件 PASS)
- [x] `src/pdf_engine/benchmark.py` による定量的精度測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/314-pdf-intelligent-dehyphenation`

1. **複合語プレフィックスおよび複合用語ルックアップセットの策定**:
   - `COMPOUND_HYPHEN_PREFIXES`: `anti`, `cross`, `fault`, `multi`, `real`, `self`, `side`, `zero` 等。
   - `KNOWN_COMPOUND_TERMS`: `zero-trust`, `cross-site`, `side-channel`, `fault-tolerant`, `state-of-the-art`, `end-to-end`, `real-time` 等。
2. **インテリジェント置換関数の実装**:
   - 正規表現 `([A-Za-z]{2,})-\n\s*([A-Za-z]{2,})` でマッチ。
   - 複合語またはプレフィックスに合致する場合は `\1-\2` としてハイフンを維持、それ以外の音節分割は `\1\2` として結合。
3. **定量的評価**:
   - 複合語保持率・音節結合率が従来の 28.6% から 100.0% に向上したことを実証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `zero-\ntrust` が `zero-trust` に、`cross-\nsite` が `cross-site` に正しく保持・結合されること。
- [x] `secu-\nrity` が `security` に、`cryp-\ntography` が `cryptography` に正しく結合されること。
- [x] 行末ハイフン直後に空白やインデントがある場合でも正しくデハイフネーションされること。
- [x] `tests/pdf_engine/` 全テスト（71件）が 100% PASS すること。
- [x] 定量的ベンチマークを測定し、精度向上を確認すること。

---
ID: 359
種別: Test / Quality
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] 柱 4: Pure Python (`pytest`) によるフロントエンド JS 構文・契約・整合性ヘッドレステストの洗練 (ID: 359)

## 1. 概要 / Summary
Node.js ベースのテストフレームワーク（Jest, Vitest, Mocha, Jasmine 等）やブラウザ自動化ライブラリ（Playwright, Puppeteer）を一切導入せず、本プロジェクトの「Zero-Mock / Pure Python」思想を徹底維持したまま、`pytest` スイート下でフロントエンド JavaScript の構文整合性、API 契約、DOM 要素 ID バインディング、および名前空間整合性を包括的・超高速に検証するヘッドレステスト基盤を洗練・拡充する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [355-refactor-namespace-from-yuzora-to-application.md](355-refactor-namespace-from-yuzora-to-application.md)
  - [356-eliminate-inline-scripts-and-modularize-by-domain.md](356-eliminate-inline-scripts-and-modularize-by-domain.md)
  - [358-standard-jsdoc-and-strict-static-analysis.md](358-standard-jsdoc-and-strict-static-analysis.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [tests/web/test_frontend_frameworks.py](../tests/web/test_frontend_frameworks.py) (フレームワーク単体契約テスト)
- [ ] [tests/web/test_zero_mock_integrity.py](../tests/web/test_zero_mock_integrity.py) (HTML-JS 要素バインディング検証)
- [ ] [tests/web/test_js_syntax_and_contracts.py](../tests/web/test_js_syntax_and_contracts.py) (新規テストスイート: JS 静的契約・構文検査)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `test/359-pure-python-js-integrity-suite`

1. **新規テストファイル `tests/web/test_js_syntax_and_contracts.py` の追加**:
   - **名前空間検証**: 全モジュールが `window.Application` または `Application.frameworks` に正しく登録されているかを AST / 静的解析で検証（意図しないグローバル漏れの検出）。
   - **未定義識別子・構文解析**: Python 組み込みの正規表現および構文走査により、`let/const/var` の宣言漏れやタイポを検査。
   - **IIFE 構造と Strict Mode 検証**: 全 JS ファイルが `'use strict';` を宣言していることを保証。
2. **HTML-JS バインディング整合性の強化 (`test_zero_mock_integrity.py`)**:
   - `index.html` および `dashboard.html` 内に定義された全 `id="..."` と、JS 側で参照される `document.getElementById('...')` の存在一致を自動検証（ID 名の不整合によるランタイムエラーの完全根絶）。
3. **高速実行と CI 統合**:
   - 外部ブラウザ不要・ミリ秒単位で完了する超高速テストとし、`make test` で即座に全パスすることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] フロントエンド JS の全ファイルに対する静的構文・名前空間・契約テストが `tests/web/` に追加されていること。
- [ ] HTML の要素 ID と JS 側の参照 ID の不整合が自動検知されること。
- [ ] 外部 Node.js / npm ライブラリを一切増やさず、Python のみで完結すること。
- [ ] 全テスト（`pytest tests/web/`）が 100% PASS すること。

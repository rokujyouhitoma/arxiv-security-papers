---
ID: 357
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] 柱 2: 外部バンドラー不要の「純粋 Python 連結・ビルドパイプライン」整備 (ID: 357)

## 1. 概要 / Summary
Node.js や npm の重量な外部バンドラー（Webpack, Vite, Rollup, esbuild 等）に依存せず、Python 標準機能（`scripts/compile_frontend.py`）のみを用いて、分割されたフロントエンド JavaScript ファイル群を安全・高効率に自動連結・圧縮（Google Closure Compiler 連携）するビルドパイプラインを確立する。
これにより、開発時は「ビルド待ち 0 秒の即時実行（Zero-Build）」、本番デプロイ時は「単一ファイル圧縮（Single-Bundle Optimization）」の両立を Pure Python で実現する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [356-eliminate-inline-scripts-and-modularize-by-domain.md](closed/356-eliminate-inline-scripts-and-modularize-by-domain.md)
  - [355-refactor-namespace-from-yuzora-to-application.md](closed/355-refactor-namespace-from-yuzora-to-application.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [scripts/compile_frontend.py](../../scripts/compile_frontend.py) (新規 Pure Python バンドル・コンパイルパイプライン)
- [x] [Makefile](../../Makefile) (`make build_js`, `make watch_js` ターゲット)
- [x] [site/app-min.js](../../site/app-min.js) (自動生成 Console プロダクションバンドル)
- [x] [site/dashboard-min.js](../../site/dashboard-min.js) (自動生成 Dashboard プロダクションバンドル)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/357-pure-python-bundling-pipeline`

1. **`scripts/compile_frontend.py` の実装**:
   - `APP_SRCS`（フレームワーク群 + マークダウンコンパイラ + `site/app.js`）および `DASHBOARD_SRCS`（フレームワーク群 + `site/js/dashboard.js`）のバンドル構成 Manifest を定義。
   - Pure Python によるファイル結合機能（`--concat-only` オプション対応）。
   - Google Closure Compiler (`tools/closure-compiler/closure-compiler-v20240317.jar`) を安全に呼び出すコンパイル機能。
   - `--watch` オプション（Python 標準ライブラリの軽量ポーリングによるファイル更新検知＆自動再コンパイル）。
2. **Makefile の更新**:
   - `build_js`: `${VENV_PYTHON} scripts/compile_frontend.py` を呼び出し。
   - `watch_js`: `${VENV_PYTHON} scripts/compile_frontend.py --watch` を呼び出し。
3. **品質検証**:
   - `make build_js` の実行確認。
   - `site/app-min.js` および `site/dashboard-min.js` の生成確認。
   - pytest 175 件 PASS 確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 分割された複数 JS ファイルが `scripts/compile_frontend.py` 経由でエラーなく 1 つのバンドルに連結・コンパイルされること。
- [x] 外部バンドラー（Webpack/Vite/Rollup等）を一切追加せずにビルドが完結すること。
- [x] `make build_js` の実行結果が再現可能（Deterministic）であること。
- [x] 全 175 件の Web 統合テストが PASS すること。

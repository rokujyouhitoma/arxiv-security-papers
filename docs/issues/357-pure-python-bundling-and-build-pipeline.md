---
ID: 357
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 柱 2: 外部バンドラー不要の「純粋 Python 連結・ビルドパイプライン」整備 (ID: 357)

## 1. 概要 / Summary
Node.js や npm の重量な外部バンドラー（Webpack, Vite, Rollup, esbuild 等）に依存せず、既存の Python 標準機能（`scripts/compile_frontend.py`）のみを用いて、分割されたフロントエンド JavaScript ファイル群を安全・高効率に自動連結・圧縮（Google Closure Compiler 連携）するビルドパイプラインを確立する。
これにより、開発時は「ビルド待ち 0 秒の即時実行（Zero-Build）」、本番デプロイ時は「単一ファイル圧縮（Single-Bundle Optimization）」の両立を Pure Python で実現する。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - [356-eliminate-inline-scripts-and-modularize-by-domain.md](356-eliminate-inline-scripts-and-modularize-by-domain.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [scripts/compile_frontend.py](../scripts/compile_frontend.py) (ビルド・連結スクリプトの拡張)
- [ ] [Makefile](../Makefile) (`make build_js`, `make watch_js` ターゲット)
- [ ] [site/app-min.js](../site/app-min.js) (自動生成プロダクションバンドル)
- [ ] [site/dashboard-min.js](../site/dashboard-min.js) (ダッシュボード用プロダクションバンドル)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/357-pure-python-bundling-pipeline`

1. **`scripts/compile_frontend.py` の機能拡張**:
   - 依存関係のトポロジカル順序に基づき、`site/js/frameworks/`、`site/js/console/`、`site/js/dashboard/` のスクリプト群を Python スクリプト内で安全に連結。
   - ソースマップ（Source Map）生成オプションのサポート（デバッグ性向上）。
   - `app-min.js` および `dashboard-min.js` を決定論的（再現可能）に生成。
2. **Makefile との統合**:
   - `make build_js`: フロントエンド全体のクリーン＆再ビルド。
   - Python 組み込みの `watchdog` または軽量ポーリングによるローカル自動コンパイル。
3. **ゼロ外部依存の保証**:
   - Python 標準ライブラリ（`pathlib`, `subprocess`, `re` 等）のみで完結させ、新規 npm パッケージの追加を厳禁。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 分割された複数 JS ファイルが `scripts/compile_frontend.py` 経由でエラーなく 1 つのバンドルに連結・コンパイルされること。
- [ ] 外部バンドラー（Webpack/Vite/Rollup等）を一切追加せずにビルドが完結すること。
- [ ] `make build_js` の実行結果が再現可能（Deterministic）であること。
- [ ] 全 175 件の Web 統合テストが PASS すること。

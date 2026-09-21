---
ID: 371
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] PyNYTProf ヒートマップ付きソースコード HTML アノテータおよび Caller/Callee 双方向レポート生成器の実装 (ID: 371)

## 1. 概要 / Summary
DSN-28（Python版NYTProf統合スイート設計仕様書）の Phase 3 として、NYTProf の最大の特徴である「ヒートマップ色分け付きソースコードアノテーション表示」「Caller / Callee 相互リンクテーブル」「Top Subroutines ランキング」を備えた自己完結型 HTML レポートビルダー `HTMLReporter`（`src/core/profiler/reporter.py`）を実装する。
外部 CDN や外部スクリプトに依存しないスタンドアロン構成であり、オフラインやエアギャップ環境でも即座にブラウザで閲覧可能とする。

---

## 2. トレーサビリティ / Traceability
- 設計仕様書: [DSN-28-python_nytprof_profiler_and_visualization_suite.md](../designs/DSN-28-python_nytprof_profiler_and_visualization_suite.md) Section 5.2 (ヒートマップ付きソースアノテーション), Section 5.3 (Caller/Callee解析)
- 関連設計: `DSN-09` (Web Gateway & Presentation), `DSN-21` (Enterprise Design System)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/core/profiler/reporter.py](../../src/core/profiler/reporter.py) (新規: 自己完結型 HTML レポート生成器)
- [x] [src/core/profiler/__init__.py](../../src/core/profiler/__init__.py) (更新: `HTMLReporter` エクスポート)
- [x] [tests/core/test_pynytprof_reporter.py](../../tests/core/test_pynytprof_reporter.py) (新規: レポート生成・XSSサニタイズ・テーブル整合性テスト)
- [x] [docs/issues/README.md](README.md) (Issue台帳の同期)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/371-pynytprof-html-reporter`

1. **ヒートマップカラー算出アルゴリズム (`reporter.py`)**:
   - 行時間比率 $P = \frac{\text{line\_time\_ns}}{\text{total\_time\_ns}} \times 100$
   - 6 段階グラデーション:
     - $P < 0.1\%$: なし (透過)
     - $0.1\% \le P < 1.0\%$: `#ffffcc` (淡黄)
     - $1.0\% \le P < 5.0\%$: `#ffe599` (黄橙)
     - $5.0\% \le P < 15.0\%$: `#f6b26b` (橙)
     - $15.0\% \le P < 30.0\%$: `#e69138` (濃橙)
     - $P \ge 30.0\%$: `#cc4125` (ホットスポット赤、白文字)

2. **Index ページ (`index.html`) の生成**:
   - メタデータカード（総時間、Python版、PID、日時、コマンドライン）。
   - インライン埋め込み Flame Graph SVG。
   - Top Subroutines テーブル（Rank, Subroutine, Calls, Inclusive Time, % Total, Exclusive Time, % Total, File）。
   - 各サブルーチン名から各ソースファイル詳細 HTML へのアンカーリンク。

3. **ソースファイル詳細ページ (`source_<id>.html`) の生成**:
   - サブルーチン要約（Caller / Callee 双方向解析テーブル: 呼出元、呼出回数、Inclusive/Exclusive 時間）。
   - 行番号、実行回数、時間、平均時間、シンタックスエスケープ済みコード行のテーブル表示。

4. **単体テストスイート (`test_pynytprof_reporter.py`)**:
   - `ProfileData` からの完全な HTML 生成とファイル出力検証。
   - `<script>` 等を含む悪意ある文字列の 100% XSS エスケープ検証。
   - Top Subroutines テーブルのソート順序・集計整合性の検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `index.html` および各ソースファイルの `source_*.html` が指定ディレクトリへ自己完結型（外部通信不要）で出力されること。
- [ ] 行ごとの消費時間に応じたヒートマップ背景色が正しく付与されること。
- [ ] サブルーチンごとの Caller/Callee テーブルが相互リンク付きで表示されること。
- [ ] `tests/core/test_pynytprof_reporter.py` が 100% パスすること。
- [ ] `make py_compile` を完全パスすること。

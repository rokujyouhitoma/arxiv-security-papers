---
ID: 833
種別: Feature
優先度: Low
ステータス: Open (New)
---

# [FEAT] コンパイラ・マクロ展開・インタプリタ共通の統合エラー診断エンジン (Diagnostic Reporter) の導入 (ID: 833)

## 1. 概要 / Summary
コンパイラの全フェーズ（字句解析・構文解析・Nanopass 中間パス・型検査）、マクロ展開器、および将来の Scheme インタプリタ REPL で共通利用可能な統合エラー診断エンジン（Diagnostic Reporter）を設計・導入する。
ソース位置情報（Source Span）と連携し、該当ソースコードのスニペット抽出、カラー表示、キャレット（`^`）および下線ハイライト、マクロ展開スタックトレース、修正提案（Fix-it ヒント）を出力する Clang / Rustc スタイルの美しい開発者体験（DX）を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §1 (フロントエンド診断基盤), §2 (B3: 構文解析, B4: 意味解析)
- **関連 Issue**: #824 (Nanopass Source Span), #823 (SRFI 64 Formatter)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/diagnostic.scm](../../ulisp/compiler/diagnostic.scm): スニペット抽出、色付きフォーマット、下線描画エンジン
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm): コンパイラドライバにおけるエラー集約・終了ステータス制御
- [ ] [ulisp/runtime/repl.scm](../../ulisp/runtime/repl.scm): インタプリタ REPL での例外キャッチとスタックトレース描画
- [ ] [ulisp/tests/test_diagnostic_reporter.scm](../../ulisp/tests/test_diagnostic_reporter.scm): 診断メッセージ出力フォーマット検証

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/833-unified-pretty-diagnostic-reporter`

1. 診断データ構造（Diagnostic Object）の定義：
   - `level`: `'error | 'warning | 'note | 'help`
   - `span`: ファイルパス、開始行/列、終了行/列
   - `message`: 人間可読なエラーメッセージ
   - `notes`: 関連する位置（例: マクロ展開元、以前の宣言箇所）
   - `suggestions`: 修正コード提案
2. スニペットレンダラの設計：
   - 該当ファイルを遅延読み込みし、対象行とその前後 1〜2 行を行番号付きで表示。
   - ANSI エスケープシーケンスによるカラー強調（`--color=auto/always/never` に対応）。
3. ドライバ・REPL との統合：
   - エラー件数・警告件数の集計と、致命的エラー時の段階的停止プロトコル。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 構文エラーやマクロ展開エラー発生時に、対象コード行とキャレット位置が明確に指し示されたスニペットが出力されること。
- [ ] `--color=never` オプションや非 TTY 出力環境において、エスケープコードを含まないプレーンテキストが生成されること。
- [ ] 単体テスト `test_diagnostic_reporter.scm` がパスすること。

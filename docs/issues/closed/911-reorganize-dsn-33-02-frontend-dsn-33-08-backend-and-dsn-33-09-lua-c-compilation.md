---
ID: 911
種別: Docs / Architecture
優先度: High
ステータス: Closed
---

# [DOCS/ARCH] DSN-33-02 (フロントエンド)・DSN-33-08 (バックエンド)・DSN-33-09 (C言語経由 Lua コンパイル) の責務分離と設計書体系化 (ID: 911)

## 1. 概要 / Summary
従来 `docs/designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md` に混在していた 3 つの関心事（多言語フロントエンド基盤、型付き機械語 LIR・多重バックエンド、および C99 フロントエンドを用いた Lua 5.x C コードベース・musl libc コンパイル）を、役割と境界に応じて以下の 3 文書へ明確に責務分離・体系化する。

- **`DSN-33-02`**: 多言語フロントエンド（C99 / Scheme）共通基盤・構文/意味解析・CTFE 設計書
- **`DSN-33-08`**: 型付き機械語 LIR・2層 Dialect 分離・ゼロコスト ABI・多重バックエンド（x86-64 / Portable C / ELF リンカ / 参照 VM）設計書
- **`DSN-33-09`**: C99 フロントエンド経由による Lua 5.x（C 言語実装）コンパイル ＆ musl libc セルフホスト実証設計書

---

## 2. トレーサビリティ / Traceability
- 上位仕様: `docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md`
- 関連設計書: `DSN-33-01` 〜 `DSN-33-07`, `DSN-33-08`, `DSN-33-09`
- 関連基盤 Issue: #824 〜 #840, #889, #890

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [DSN-33-02](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md) (フロントエンド専用へ再編)
- [x] [DSN-33-08](../designs/DSN-33-08-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md) (新規作成: バックエンド設計書)
- [x] [DSN-33-09](../designs/DSN-33-09-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md) (新規作成: Lua C コンパイル設計書)
- [x] [DSN-33](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) および `DSN-33-01` 〜 `DSN-33-07` (関連個別仕様書リンク更新)
- [x] [Issue 台帳](README.md)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `docs/911-reorganize-dsn-33-02-08-09-architecture`

1. `DSN-33-08` を新規作成し、`DSN-33-02` から LIR、Dialect 分離、値表現プラグイン、SysV ABI、ELF セクション、Braun SSA、PassManager キャッシュ、参照 VM、C バックエンド差分ファジング、および DSN-33-03 ブリッジ仕様を移管・詳述する。
2. `DSN-33-09` を新規作成し、フロントエンドで Lua 構文を直接扱うのではなく、C99 フロントエンドで公式 Lua 5.x の C ソースコードをコンパイルし、musl libc と結合してセルフホスト実証を行うための要件（マクロ展開、構造体レイアウト、関数ポインタ、`setjmp`/`longjmp`、`va_list`、XMM、S0〜S9 ロードマップ、4大裁定規準、DDC）を移管・体系化する。
3. `DSN-33-02` をフロントエンド専用設計書（Source Span、Binding ID、CTFE、数値塔、Diagnostic、PCH、および Scheme / C99 フロントエンド構成）として整理し、`DSN-33-08` および `DSN-33-09` への相互参照を整備する。
4. `DSN-33` 親文書および `DSN-33-01`〜`DSN-33-07` の関連仕様書一覧を更新する。
5. `verify-quality-gates`（絶対パスリンク 0 件、`make py_compile` 通過）を検証し、Issue をクローズして `main` へマージする。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `DSN-33-02` がフロントエンド仕様に純化され、バックエンド・Lua C コンパイル仕様がそれぞれ `DSN-33-08`・`DSN-33-09` に整理されていること。
- [x] `DSN-33-09` に「フロントエンドで C 言語をサポートした上で Lua の C コードをコンパイルする」スコープが明確に規定されていること。
- [x] `DSN-33` 系各設計書の関連個別仕様書リストが整合していること。
- [x] すべての Markdown ドキュメントで絶対パスリンクが 0 件であること。
- [x] `make py_compile` が正常終了すること。

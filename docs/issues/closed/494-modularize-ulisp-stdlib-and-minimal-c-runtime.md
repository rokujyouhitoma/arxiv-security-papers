---
ID: 494
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp 標準ライブラリ (lib/) の独立分離と極小 C ランタイム (Thin Debug Runtime) への刷新 (ID: 494)

## 1. 概要 / Summary

[DSN-33: ULISP x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、現在 `runtime.c`（約400行）に依存している Scheme 言語機能（S式リーダー、出力フォーマッタ、文字列・数値変換、シンボル管理）を Scheme 自身の標準ライブラリ（`ulisp/lib/`）として独立分離・モジュール化する。

同時に、開発・デバッグ時の強力な支援機能である「セグフォ時のレジスタ・スタックダンプおよび `backtrace` 表示機能」を確実に維持したまま、C言語の役割をシグナルハンドラ設定・入力ファイル切り替え・初期ヒープ確保のみを行う約40〜50行の「極小デバッグ・ランタイム（Thin Debug Runtime）」へとスリム化する。

これにより、C言語依存度を90%以上削減し、セルフホスティング処理系としての言語的自立度・再利用性・純度を高めつつ、不具合発生時の迅速な障害解析能力（DX）を両立させる。

---

## 2. トレーサビリティとセキュリティ・設計制約 / Traceability & Constraints

### 2.1 関連設計書・先行 Issue
- 関連仕様書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- 先行 Issue:
  - [Issue 493: ULisp Phase 7 セルフホスティングブートストラップ連鎖と不動点検証](closed/493-implement-ulisp-phase7-self-hosting-bootstrap-and-fixed-point.md)

### 2.2 セキュリティ・頑健性要件（脅威モデル考慮）
- **バッファオーバーフロー防御**:
  現在 `runtime.c` の `tok[1024]` や `buf[4096]` などの固定長バッファで行われていたトークン読み取りを、Scheme 側でリスト構造（可変長）で処理することで、長大なシンボルや文字列による C バッファオーバーラン脆弱性を原理的に排除する。
- **デバッグ情報の漏洩防止**:
  クラッシュハンドラ（`SIGSEGV`）は開発・テスト時の `stderr` 出力に限定し、本番配備時（将来の `ULISP_RELEASE`）では静かに終了（またはセーフティフェイル）できる切り替え構造を維持する。
- **ブートストラップ決定論性**:
  標準ライブラリ（`lib/`）を導入しても、Stage 2 と Stage 3 のコンパイル結果は 1 バイトの差分もなく完全一致（差分ゼロ）しなければならない。

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/lib/string.scm](../../ulisp/lib/string.scm) (新規作成: `string-append`, `number->string`, `symbol->string`, `string->symbol`, `escape-gas-string`)
- [ ] [ulisp/lib/printer.scm](../../ulisp/lib/printer.scm) (新規作成: `write-char`, `display`, `write`, `newline` 等の Scheme フォーマッタ)
- [ ] [ulisp/lib/reader.scm](../../ulisp/lib/reader.scm) (新規作成: `read-char`, `peek-char` をベースとする自前 S 式パーサ `read`)
- [ ] [ulisp/runtime.c](../../ulisp/runtime.c) (刷新: クラッシュハンドラ、ヒープ確保、`scheme_entry`、最小 I/O 3プリミティブのみの Thin Runtime 化)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (改修: C プリミティブ特別扱いを撤廃し、`lib/` で定義された Scheme 関数への通常ディスパッチ化)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (ビルド改修: `lib/*.scm` と `compiler.scm` の結合ビルドルールおよびテスト自動化)
- [ ] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (ブートストラップ改修: 新構成での Stage 1〜Stage 3 diff ゼロ検証)
- [ ] [ulisp/test.sh](../../ulisp/test.sh) (テスト改修: `lib/` 結合後の各ステップ全件合格確認)
- [ ] [docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (仕様改定: Thin C Debug Runtime 構造の反映)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/494-modularize-ulisp-stdlib-and-minimal-c-runtime`

### Phase 1: 極小 C ランタイム（Thin Debug Runtime）の仕様確定
`ulisp/runtime.c` に残す責任を以下の 4 点に限定する（約 50 行）：
1. **クラッシュハンドラ (`crash_handler`)**:
   - `SIGSEGV` 受信時に `ucontext_t` から RIP / RSP / RAX / RDX を取得し `stderr` へ出力。
   - `backtrace` と `backtrace_symbols_fd` で C/アセンブリスタックトレースを出力。
2. **最小 I/O プリミティブ（3個のみ）**:
   - `ulisp_read_char`: `getchar()`
   - `ulisp_peek_char`: `getchar()` + `ungetc()`
   - `ulisp_write_char`: `putchar()`
3. **エントリポイント (`main`)**:
   - 引数処理（`argv[1]` の `freopen` 入力リダイレクト）
   - `malloc(128MB)` による初期バンプヒープ確保
   - `scheme_entry(heap)` 呼び出し

### Phase 2: 標準ライブラリ (`ulisp/lib/`) の実装
1. **`ulisp/lib/string.scm`**:
   - `(number->string n)`: 負数対応、除算・剰余（`quotient`/`modulo`）による桁分解と文字リストからの文字列構築。
   - `(string-append2 s1 s2)` / `(string-append ...)`: Scheme レベルでの文字列連結。
   - `(escape-gas-string s)`: アセンブリの `.asciz` 出力用に `\n`, `\t`, `"` などのエスケープ処理。
   - `(symbol->string sym)` / `(string->symbol str)`: 連想リストによるシンボルインターン管理。
2. **`ulisp/lib/printer.scm`**:
   - `(newline)`: `(write-char #\newline)`
   - `(display val)`: 文字列・シンボル・数値をそのまま表示。
   - `(write val)`: リスト `(a b c)`、ペア `(a . b)`、クォート、ブール値 `#t`/`#f`、空リスト `'()` を再帰的に整形表示。
3. **`ulisp/lib/reader.scm`**:
   - `(skip-whitespace-and-comments)`: 空白文字および `;` コメントのスキップ。
   - `(read)`: トークン分解と再帰下降パーサ。
     - 丸括弧 `(...)`、ドットペア `(a . b)`
     - クォート `'datum`
     - 文字列 `"..."`
     - 文字リテラル `#\space`, `#\newline`, `#\a`
     - 真偽値 `#t`, `#f`
     - 数値リテラル、シンボルリテラル

### Phase 3: コンパイラ（`compiler.scm`）とビルドパイプラインの統合
1. **プリミティブ特別扱いの整理**:
   - `compiler.scm` の `compile-zero-arg`, `compile-unary`, `compile-binop` から、C 関数を直接呼んでいた `ulisp_read`, `ulisp_display`, `ulisp_number_to_string` 等の専用コードを廃止。
   - 代わりに `read-char`, `peek-char`, `write-char` のみ最小 C プリミティブとして残し、他は通常の Scheme 手続き呼び出しへ統合。
2. **Makefile でのモジュール結合**:
   - `build/ulisp_core.scm` = `lib/string.scm` + `lib/printer.scm` + `lib/reader.scm` + `compiler.scm`
   - 単一スクリプトとして ILisp および Stage 1 ネイティブバイナリに供給。
3. **3段階ブートストラップ不動点検証**:
   - `./bootstrap.sh` を新構成で実行し、`diff stage2.s stage3.s` が 0 バイト差分であることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] **ライブラリ分離**:
  - `ulisp/lib/string.scm`, `ulisp/lib/printer.scm`, `ulisp/lib/reader.scm` が作成され、Scheme 自身で記述されていること。
- [x] **C ランタイムのスリム化**:
  - `ulisp/runtime.c` のコード行数が圧縮され、S式パース・フォーマット・シンボルテーブルが完全に排除され、最小 3 I/O primitives + デバッグ機能のみに純化されていること。
- [x] **クラッシュハンドラ動作確認**:
  - 不正メモリアクセス発生時に、RIP/RSP/RAX およびスタックバックトレースが `stderr` に出力されることが保たれていること。
- [x] **テスト完全パス**:
  - `cd ulisp && ./test.sh` の全テストスイートが 100% PASS すること。
- [x] **不動点検証の維持**:
  - `cd ulisp && ./bootstrap.sh` において `Stage 2 vs Stage 3: MATCH (diff stage2.s stage3.s is empty)` が確認されること。
- [x] **設計書同期**:
  - [DSN-33](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に「Thin C Debug Runtime ＆ lib/ 標準ライブラリ構成」が反映されていること。

---

## 6. 作業ログ / Work Log

- 2026-10-07: Issue 作成 (ID: 494)
- 2026-10-07: `polish-issue` により詳細実装方針（Phase 1〜3）、セキュリティ・設計制約、および DoD を策定。ステータスを `Open (In Progress)` に更新。
- 2026-10-08:
  - `ulisp/lib/string.scm`, `printer.scm`, `reader.scm` の独立モジュール化を完了。
  - `runtime.c` を Thin Debug Runtime 化（クラッシュバックトレース保持、HEAP_SIZE 1GB 拡張、最小 3 I/O primitives）。
  - `compiler.scm` に `integer->symbol`, `symbol->integer` プリミティブを追加し、シンボルタグ整合性と TCO 呼び出し规約を完全準拠化。
  - `./test.sh`（Step 1〜24 全テスト）および `./bootstrap.sh`（Stage 1〜3 3段階ブートストラップ不動点ビット完全一致 0 バイト差分）の 100% パスを検証完了。
  - [DSN-33](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) 設計書と同期完了。Issue クローズ。

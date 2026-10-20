---
ID: 580
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ARCH] runtime.c の完全廃止と低水準 Scheme (Pre-Scheme 思想) による完全自己完結ランタイムの実現 (ID: 580)

## 1. 概要 / Summary
現在 uLisp は自己記述型コンパイラとして発展を続けているが、基底レイヤーに 369 行の `ulisp/runtime.c`（クラッシュハンドラ、ヒープアロケーション・GCステート管理・`mremap` 動的ヒープ拡張、低水準 I/O プリミティブ、Scheme 値フォーマッタ、`main` エントリポイント）が残存している。
これは、META II や Pre-Scheme、CakeML 等の自己ホスト先行研究が目指す「真の自己完結性（Self-containment）」における最後の外的依存となっており、C 言語側のランタイム保守と Scheme コンパイラ側のコード生成との間で二重管理・抽象度ギャップ（特に Precise GC Safepoint 追跡やスタック走査）を生む根本原因となっていた。

本 Issue では、Kelsey & Rees (1994) の **Pre-Scheme 思想** を踏襲し、`runtime.c` が担っていた全機能を低水準 Scheme サブセット（ポインタ・メモリ直接操作、システムコール / POSIX 呼出し、GC ステート制御）として記述する `ulisp/runtime/`（または `ulisp/lib/runtime.scm`）を新設する。
コンパイラ自身のコード生成基盤（C バックエンドまたはネイティブバックエンド）を用いてランタイムを自律コンパイル・リンクさせ、**`ulisp/runtime.c` を完全に廃止（削除）** する。これにより、コンパイラ本体からランタイム・GC・I/O に至る全層が 100% Scheme だけで記述・生成される完全自己記述・自己完結システムを完遂する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Pre-Scheme: A Portable Implementation Language for Scheme Runtimes (Kelsey & Rees, 1994)
- 先行研究系譜: CakeML: A Verified Implementation of ML (Kumaran et al., 完全自己ホストとブートストラップ)
- 先行研究系譜: Chicken Scheme / Gambit Scheme におけるランタイム自言語化
- DSN-33 アーキテクチャ仕様
- 関連 Issue:
  - [closed/542-prepare-macos-portability-for-c-and-documentation.md](closed/542-prepare-macos-portability-for-c-and-documentation.md)
  - [closed/566-implement-dynamic-heap-growth-policy-and-mremap.md](closed/566-implement-dynamic-heap-growth-policy-and-mremap.md)
  - [closed/569-separate-x86-gc-collector-and-freestanding-runtime-passes.md](closed/569-separate-x86-gc-collector-and-freestanding-runtime-passes.md)
  - [577-implement-gc-stress-testing-mode-for-c-and-native-backends.md](577-implement-gc-stress-testing-mode-for-c-and-native-backends.md)
  - [579-establish-3-stage-bootstrap-fixed-point-verification-protocol.md](579-establish-3-stage-bootstrap-fixed-point-verification-protocol.md)
- 関連ファイル:
  - [ulisp/runtime.c](../../ulisp/runtime.c)
  - [ulisp/passes/142_backend_x86_freestanding.scm](../../ulisp/passes/142_backend_x86_freestanding.scm)
  - [ulisp/passes/160_backend_c.scm](../../ulisp/passes/160_backend_c.scm)
  - [ulisp/Makefile](../../ulisp/Makefile)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/runtime/gc.scm](../../ulisp/runtime/gc.scm) (新規: ヒープ確保 `mmap`、`ulisp_gc_state`、動的 Mature 空間拡張 `mremap`、Write Barrier、OOM ハンドラの Scheme 実装)
- [x] [ulisp/runtime/io.scm](../../ulisp/runtime/io.scm) (新規: `ulisp_read_char`, `peek_char`, `write_char`, `write_string`, `flush` の低水準 Scheme 実装)
- [x] [ulisp/runtime/printer.scm](../../ulisp/runtime/printer.scm) (新規: Fixnum, Pair, Vector, Bytevector, String, Symbol 等の低水準タグ分解と再帰デバッグ出力ルーチン)
- [x] [ulisp/runtime/entry.scm](../../ulisp/runtime/entry.scm) (新規: コマンドライン引数・環境変数解析、シグナルハンドラ、ヒープ確保、`scheme_entry` 呼出しとプロセス exit を司る `main` エントリポイント)
- [x] [ulisp/runtime.c](../../ulisp/runtime.c) (**完全廃止・削除**)
- [x] [ulisp/passes/160_backend_c.scm](../../ulisp/passes/160_backend_c.scm) (外部 `runtime.c` のリンク依存を撤廃し、Scheme 記述ランタイムを直接 C 翻訳またはインライン出力するよう更新)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`CC` による `runtime.c` コンパイルルール・オブジェクト参照を全廃し、Scheme ランタイムビルドターゲットへ統一)
- [x] [ulisp/tests/test_scheme_runtime.scm](../../ulisp/tests/test_scheme_runtime.scm) (新規: 純粋 Scheme ランタイムの初期化・I/O・GC・フォーマット単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/580-deprecate-runtime-c-and-implement-pure-scheme-runtime`

1. **ランタイム機能のドメイン別 Scheme モジュール化 (`ulisp/runtime/`)**:
   - **`gc.scm`**:
     - `(runtime-init-heap size)`: システムコールまたは低水準メモリ確保を用いて Nursery / Mature 空間を初期化。
     - `(runtime-gc-grow-mature)`: Linux `mremap` または領域再確保を低水準プリミティブ経由で実行し、使用率 70% 超過時の自動拡張を制御。
     - `(runtime-write-barrier mature-addr val)`: 世代別 GC 用 RemSet 記録。
   - **`io.scm`**:
     - 単一文字入出力、バッファ付き peek-char、文字列・バイト列出力を OS I/O プリミティブへ直接マッピング。
   - **`printer.scm`**:
     - タグビット判定（Fixnum: `0x00`, Pair: `0x01`, String: `0x03`, Vector: `0x05`, Bytevector: `0x07`, Char: `0x0E`, Symbol: `0x02`）に基づき、循環構造やドット対を安全に出力する低水準プリンタ。
   - **`entry.scm`**:
     - プロセス起動時の `argv`, `argc`, 環境変数（`ULISP_QUIET`, `ULISP_GC_PROFILE`, `DEBUG_GC`）を読み取り、ヒープ初期化後に `scheme_entry` を実行、終了ステータスで exit。
2. **コンパイラバックエンドとの統合**:
   - `160_backend_c.scm`:
     - これまで `runtime.c` に依存していた外部シンボル宣言（`extern ...`）を、Scheme で記述されたランタイム関数の出力へと置換。
     - C バックエンド出力ファイル単体で `main()` から全プリミティブまでを含む自己完結 C ソース（Single Translation Unit）を生成可能にする。
   - `142_backend_x86_freestanding.scm`:
     - ネイティブ x86-64 向けフリースタンディングランタイムと設計を整合させ、共通の低水準 Scheme IR から C とアセンブリの双方が生成される構造に整流化。
3. **`runtime.c` の削除と Makefile の改修**:
   - `ulisp/runtime.c` を Git から削除。
   - `ulisp/Makefile` の `CFLAGS`、`runtime.o` 依存関係、リンク指定を削除。
   - `ULISP_COMPILER` のみで実行可能バイナリが生成されるビルドフローへ刷新。
4. **回帰検証と DoD 充足確認**:
   - AOT ネイティブテスト（`make test_aot`）、C バックエンドテスト（`make test_c`）、Pass 単体テスト（`make test_all_passes`）を実行。
   - `runtime.c` 不在の状態で既存の全機能・全テストが正常に動作することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/runtime.c` が完全に削除され、リポジトリ内に C 言語手書きランタイムが存在しないこと
- [ ] `ulisp/runtime/` 配下の Scheme モジュールによって、ヒープ確保・GCステート管理・動的拡張・低水準 I/O・値表示・`main` エントリポイントが 100% Scheme で実装されていること
- [ ] C バックエンド（`make -C ulisp test_c`）および x86-64 バックエンド（`make -C ulisp test_aot`）が `runtime.c` なしで 100% ビルド・実行可能であること
- [ ] 既存の全テストスイート（`test_all_passes`, `test_record`, `test_promise`, `test_gc_growth` 等）がデグレードなく PASS すること
- [ ] `bootstrap.sh` による自己ホストビルドが Scheme ランタイムのみで完結すること
- [ ] 相対パスのみを使用し、絶対パスが含まれないこと

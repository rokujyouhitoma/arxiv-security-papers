---
ID: 604
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラ実行時のコールスタック追跡（Call Stack Traceback）および未捕捉例外時のバックトレース表示機能の実装 (ID: 604)

## 1. 概要 / Summary
現在、ULisp ネイティブ実行系およびコンパイラ内部において例外が発生した際、スタックトレース（呼び出し履歴・バックトレース）が記録・表示されないため、エラーがどの関数のどのような呼び出し経路を辿って発生したのかを把握するのが極めて困難である。

本 Issue では、コンパイラ実行時（またはデバッグモード `--debug` / `ULISP_DEBUG=1` 時）に関数呼び出しフレームを追跡・記録するコールスタック管理機構を導入し、未捕捉例外（`unhandled exception`）の発生時に呼び出し元の関数名チェーン（Backtrace）を順序立てて出力する機能を実装する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [R7RS 例外仕様準拠ドキュメント](../../ulisp/docs/r7rs_specification_compliance.md)
- **関連 Issue**:
  - Issue 531: 軽量大域脱出ハンドラスタックに基づく R7RS 例外処理機構の実装
  - Issue 540: スタック退避・復元および動的巻き戻しに基づく完全第一級 call/cc の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (コールスタック追跡フレームのデータ構造と push/pop ユーティリティ)
- [ ] [ulisp/lib/exception.scm](../../ulisp/lib/exception.scm) (Condition オブジェクトへのバックトレース情報添付)
- [ ] [ulisp/backend/142_backend_x86_freestanding.scm](../../ulisp/backend/142_backend_x86_freestanding.scm) (`ulisp_unhandled_exception` におけるスタックダンプ支援)
- [ ] [ulisp/tests/passes/test_traceback.scm](../../ulisp/tests/passes/test_traceback.scm) (新規: バックトレース出力テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/604-implement-call-stack-traceback-for-compiler-exceptions`

1. **軽量コールスタック追跡構造の導入**:
   - `with-call-frame name thunk` 構文または Nanopass 呼び出しラッパーを用意。
   - `*call-stack*` パラメータに直近の関数呼び出し名（最大 16〜32 フレーム）をリングバッファまたはリストとして蓄積。
2. **例外オブジェクト（Condition）へのトレースバック統合**:
   - `raise` / `error` 呼び出し時に、現在の `*call-stack*` のスナップショットを Condition 内に自動保存。
3. **バックトレースフォーマッタの実装**:
   - 未捕捉例外発生時、以下のようなスタックトレースを出力：
     ```text
     Call Traceback (most recent call last):
       [5] (compile-top-level '(define (my-func x) ...))
       [4] [Pass 130: LIR Generation] (lir-compile-function ...)
       [3] (lir-compile-expr '(car ls) ...)
       [2] (lir-compile-variable 'car env)
       [1] (error "Unbound variable in LIR: car" 'car)
     ```
4. **性能影響の極小化**:
   - デバッグフラグオフ時はオーバーヘッドがゼロ、または定数時間となるよう設計。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 未捕捉例外発生時に、最新の呼び出し階層（Backtrace）が番号付きで標準エラーに出力されること。
- [ ] 通常コンパイル時（非デバッグモード時）の実行速度に影響を与えないこと。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。

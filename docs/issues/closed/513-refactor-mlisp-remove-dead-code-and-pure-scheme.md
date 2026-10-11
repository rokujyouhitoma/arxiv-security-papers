---
ID: 513
種別: Refactor
優先度: Medium
ステータス: Closed (Completed)
---

# [REFACTOR] MLisp コードベースの純化・重複解消および不要コードの完全排除 (ID: 513)

## 1. 概要 / Summary
MLisp ツールチェーンの成熟に伴い、コードベースの保守性と設計純度を向上させるリファクタリングを実施した：
1. **不要コードの削除**:
   - `mlisp/driver/compile_ulisp_runner.scm` (132 KB, 3,464行の完全なデッドコード) を削除。
   - `mlisp/driver/scheme_jit.scm` (旧プロトタイプ) を削除し、`Makefile` のビルドターゲットを最新の `ulisp-jit` に一本化。
2. **モジュールの純化（Pure Scheme 化）と重複解消**:
   - `mlisp/core/delimcc.scm`、`mlisp/tracer/tracer.scm`、`mlisp/optimizer/pe.scm`、`mlisp/optimizer/virtuals.scm`、`mlisp/bridge/to_lir.scm` に残存していた準クオート（`` ` ``）を `list` / `cons` / `append` にリファクタリング。
   - ホスト環境（Python `ilisp`）とネイティブ AOT 環境（`ulisp` Nanopass コンパイラ）で 100% 共通利用可能な Pure Scheme に統一。
   - 全94テストスイートおよび AOT / JIT 双方の検証パスが 100% PASS することを確認。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-34: MLisp 内因的メタトレーシング JIT アーキテクチャ仕様書](../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- 関連 Issue: [Issue 512: ULisp AOT コンパイラと MLisp JIT エンジンを統合したワンバイナリ (ulisp-jit) の構築と性能比較評価](closed/512-integrate-ulisp-aot-and-mlisp-jit-one-binary.md)
- 関連 Issue: [Issue 508: MLisp の AOT 統合および JIT 内蔵型ワンバイナリ (scheme-jit) の生成](closed/508-integrate-mlisp-with-ulisp-aot-compiler.md)
- 関連 Issue: [Issue 509: MLisp JIT 実行基盤による ULisp コンパイラ (compiler.scm) のコンパイルと自己ホスティングバイナリ出力](closed/509-compile-ulisp-compiler-via-mlisp-jit.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [mlisp/driver/compile_ulisp_runner.scm](../../mlisp/driver/compile_ulisp_runner.scm) (削除)
- [x] [mlisp/driver/scheme_jit.scm](../../mlisp/driver/scheme_jit.scm) (削除)
- [x] [mlisp/Makefile](../../mlisp/Makefile) (不要ターゲット整理)
- [x] [mlisp/core/delimcc.scm](../../mlisp/core/delimcc.scm) (準クオート純化)
- [x] [mlisp/tracer/tracer.scm](../../mlisp/tracer/tracer.scm) (準クオート純化)
- [x] [mlisp/optimizer/pe.scm](../../mlisp/optimizer/pe.scm) (準クオート純化)
- [x] [mlisp/optimizer/virtuals.scm](../../mlisp/optimizer/virtuals.scm) (準クオート純化)
- [x] [mlisp/bridge/to_lir.scm](../../mlisp/bridge/to_lir.scm) (準クオート純化)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/513-clean-mlisp-and-pure-scheme`

1. **不要ファイルの安全な削除**:
   - `git rm mlisp/driver/compile_ulisp_runner.scm`
   - `git rm mlisp/driver/scheme_jit.scm`
   - `mlisp/Makefile` から `driver/scheme_jit.scm` を削除し、`scheme-jit` ターゲットを `ulisp-jit` に統合。
2. **個別モジュールの Pure Scheme 化**:
   - `core/delimcc.scm`: `reset`, `shift` マクロから準クオートを排除。
   - `tracer/tracer.scm`: `(%guard ...)`, `(%trace-loop-entry ...)` 等を `list` に変更。
   - `optimizer/pe.scm`: `(%mov ...)`, `(,op ...)` 等を `list` / `cons` に変更。
   - `optimizer/virtuals.scm`: 仮想オブジェクト巻き戻し箇所の準クオートを `list` に変更。
   - `bridge/to_lir.scm`: `(%lir-program ...)` を `list` / `cons` に変更。
3. **品質検証**:
   - `make -C mlisp test` (全94テストが 100% PASS)
   - `make -C mlisp run_ulisp_jit` (JIT実行 & AOTコンパイルの双方 PASS)

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `mlisp/driver/compile_ulisp_runner.scm` および `mlisp/driver/scheme_jit.scm` が完全に削除されていること
- [x] `mlisp/tracer/`, `mlisp/optimizer/`, `mlisp/bridge/` 配下から準クオート（`` ` ``）が 100% 排除されていること
- [x] `make -C mlisp test`（全94テスト）が正常に合格すること
- [x] `make -C mlisp run_ulisp_jit` で JIT 実行および AOT コンパイルが正常動作すること
- [x] 全品質ゲート（静的解析・テスト）が PASS すること

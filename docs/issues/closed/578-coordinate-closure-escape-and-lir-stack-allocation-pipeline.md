---
ID: 578
種別: Refactor
優先度: Medium
ステータス: Closed
---

# [REFACTOR] Pass 110 (Closure) / 120 (Escape) / 130 (LIR) の連携による非エスケープオブジェクトのスタック配置最適化 (ID: 578)

## 1. 概要 / Summary
uLisp における現在のコンパイルパイプラインは、`110_closure_convert.scm`（クロージャ変換）の直後に `120_alias_escape.scm`（エイリアス・エスケープ解析）が配置されている。
しかし、先行研究（Nanopass および多段 IR 設計）の観点から見ると、Pass 110 で正規化・生成されたクロージャ環境オブジェクト（コードポインタと自由変数タプル）が、Pass 120 のエスケープ解析結果（スコープ外へ流出しないという情報）を十分に活用して下流へ引き渡す契約が未確立であった。その結果、短命な局所クロージャや一時タプルであっても常にヒープ `%alloc` が要求され、GC プレッシャーの原因となっていた。

本 Issue では、Pass 110、120、130 間の協調設計を再編し、「Pass 110 が明示的環境オブジェクトへ正規化」→「Pass 120 がエスケープの有無を静的判定して `#:stack-alloc` 属性を付与」→「Pass 130 (LIR) が当該オブジェクトをヒープ `%alloc` ではなくスタックフレーム（`%alloca`）への直接配置命令へフォールバック」させる最適化パイプラインを確立する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: Escape Analysis for Object Allocation (Choi et al., OOPSLA / Chez Scheme)
- 先行研究系譜: Contification and Closure Conversion (Kennedy / Fluet et al.)
- DSN-33 コンパイラ仕様
- 関連ファイル:
  - [ulisp/passes/110_closure_convert.scm](../../ulisp/passes/110_closure_convert.scm)
  - [ulisp/passes/120_alias_escape.scm](../../ulisp/passes/120_alias_escape.scm)
  - [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm)
  - [ulisp/tests/passes/test_110_closure_convert.scm](../../ulisp/tests/passes/test_110_closure_convert.scm)
  - [ulisp/tests/passes/test_120_alias_escape.scm](../../ulisp/tests/passes/test_120_alias_escape.scm)
  - [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/110_closure_convert.scm](../../ulisp/passes/110_closure_convert.scm) (クロージャ環境タプルおよび生成ノードの正規化タグ整備)
- [x] [ulisp/passes/120_alias_escape.scm](../../ulisp/passes/120_alias_escape.scm) (Pass 110 の環境表現に対するエスケープ解析、`#:stack-alloc` 注釈の付与)
- [x] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm) (`#:stack-alloc` 注釈ノードを検知し、スタックフレーム領域割当 LIR 命令を発行)
- [x] [ulisp/tests/passes/test_120_alias_escape.scm](../../ulisp/tests/passes/test_120_alias_escape.scm) (エスケープ判定とスタック注釈付与の単体テスト追加)
- [x] [ulisp/tests/passes/test_130_lir.scm](../../ulisp/tests/passes/test_130_lir.scm) (スタック割当 LIR 命令出力の検証テスト追加)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `refactor/578-coordinate-closure-escape-and-lir-stack-allocation-pipeline`

1. **Pass 110 の正規化タグ付け (`110_closure_convert.scm`)**:
   - `make-closure` 式を `(%make-closure-env <lambda-label> <free-vars...>)` 形式として明示化。
   - 解析情報が欠落しないよう、識別用メタデータスロットを確保。
2. **Pass 120 のエスケープ解析強化 (`120_alias_escape.scm`)**:
   - レキシカルスコープ内で即時呼び出しされるクロージャ、または高階関数へ渡されるが戻り値やグローバル変数に格納されないクロージャを走査。
   - 非エスケープと判定されたクロージャ環境に `(annotate #:stack-alloc (%make-closure-env ...))` を付与。
3. **Pass 130 の LIR 低水準化 (`130_lir.scm`)**:
   - 通常の `%make-closure-env` はヒープ `%alloc` の LIR を発行。
   - `#:stack-alloc` 注釈が付与されている場合は、スタックポインタ相対のローカルバッファ（`%alloca` / スタックオフセット参照）を生成し、GC ルート追跡対象外とする（または専用スタックスロットにマッピング）。
4. **テスト検証**:
   - `test_120_alias_escape.scm` でエスケープ・非エスケープの二極が正しく識別・注釈されることをテスト。
   - `test_130_lir.scm` で LIR 命令列の分岐出力をテスト。
   - ベンチマーク等でヒープアロケーション回数の削減を確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 非エスケープクロージャに対して Pass 120 が正しく `#:stack-alloc` を付与できること
- [x] Pass 130 が `#:stack-alloc` 注釈を認識し、ヒープ割当（`%alloc`）を回避する LIR を出力すること
- [x] 全27パスの単体テスト（`make -C ulisp test_all_passes`）が 100% PASS すること
- [x] 既存の AOT テストスイート（`make -C ulisp test_aot`）がデグレードなく 100% PASS すること
- [x] 相対パスのみを使用し、絶対パスが含まれないこと

---

## 6. 検証結果 / Verification Results
- `make -C ulisp test_all_passes`: 33/33 PASS (100%)
- `./test_c.sh`: 139/139 PASS (100% with -Werror)
- `./bootstrap.sh`: Stage 2 と Stage 3 の bit-for-bit IDENTICAL 固定点収束を完全達成、スモークテスト (Exit code 42) PASS
- `./test.sh`: 全 35 ステップ完走 PASS

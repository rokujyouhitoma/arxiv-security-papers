---
ID: 916
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] C99 基本型検査・整数昇格 (Sema Core) および整数サブセット Core LIR Lowering の実装 (ID: 916)

## 1. 概要 / Summary
C99 AST（`L_c_ast`）に対して基本型検査・暗黙の整数昇格（Integer Promotion）・通常の算術変換を施して型付き中間表現 `L_c_typed` を生成する意味解析器（`ulisp/frontend_c/sema.scm`）と、整数演算・制御構造・文字列リテラル・`printf` 等の外部 `'sysv` 呼び出しを `DSN-33-13` **Core Machine LIR** へ降格する Lowering エンジン（`ulisp/frontend_c/lower_to_lir.scm`）を実装する（Phase S2 / Task T4）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.4, §6.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-11 §4.2, §4.3](../designs/DSN-33-11-ulisp_multilingual_frontend_and_ctfe_architecture.md)
  - [DSN-33-13 §2.1, §3.2, §4.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤（実装済・先行）:
  - `#826`: Typed Machine LIR（[ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm)）
  - `#827`: Pass 132 Braun SSA（[ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)）
  - `#828`: オーバーフロー検知 ＆ 符号なし演算オペコード（[ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm)）
  - `#829`: SysV 呼出規約（[ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）
  - `#834`: Reference VM（[ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm)）
  - `#835`: Core Machine LIR と Managed Runtime Dialect の完全分離（[ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm)）
  - `#915`: C99 Parser ＆ `L_c_ast`（[[#915]](915-implement-c99-parser-and-nanopass-c-ast-definitions.md)）
- 後続連携 Issue:
  - [[#917]](917-implement-c-compiler-driver-and-host-ld-integration.md) (`c_driver.scm`), [[#918]](918-implement-c99-struct-union-enum-bitfield-sysv-layout.md), [[#919]](919-implement-c99-pointer-scaling-array-decay-and-escape-analysis.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/c_lang.scm` (`<c-type>` 型表現および `define-language L_c_typed` 追加)
- [ ] `ulisp/frontend_c/sema.scm` (新規: 基本型検査・整数昇格・通常の算術変換・`c99-analyze-program`)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (新規: `L_c_typed` → Core Machine LIR 降格 `c99-lower-to-lir`)
- [ ] `ulisp/tests/test_c99_int_lowering.scm` (新規: Reference VM #834・`lir_verifier`・x86-64/C 実行検証)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`test_c99_int_lowering` ターゲットおよび `test` 集約への登録)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/916-implement-c99-sema-core-and-int-lowering`

### 4.1 型システム ＆ 意味解析 (`ulisp/frontend_c/sema.scm`, `c_lang.scm`)
1. **`<c-type>` 型表現**:
   - `'void`, `'i8`, `'u8`, `'i16`, `'u16`, `'i32`, `'u32`, `'i64`, `'u64`, `(ptr target)`, `(array elem len)`, `(fn ret params variadic?)` と型サイズ/アライメント計算手続き `(c-type-size t)`, `(c-type-align t)`, `(c-type->lir-ty t)`。
2. **`define-language L_c_typed (extends L_c_ast)` ＆ `(c99-analyze-program ast)`**:
   - 式ノードへ決定済み `<c-type>` 注釈を付与し、明示的な型変換ノード `(c-implicit-cast target-type expr)` を挿入する。
   - **整数昇格 (ISO C99 §6.3.1.1)**: `char`/`short`/`_Bool`（`i8`/`u8`/`i16`/`u16`）を演算時に `int` (`i32`) へ昇格。
   - **通常の算術変換 (Usual Arithmetic Conversions, §6.3.1.8)**: ランクおよび符号有無ルールに従い `%sext` / `%zext` / `%trunc` の対象型を確定。
   - **左辺値チェック ＆ 関数プロトタイプ検査**: 代入左辺および `++`/`--` 対象が代入可能左辺値であることを検証し、未宣言識別子や型不整合は `diagnostic.scm`（#833）経由で報告。

### 4.2 Core Machine LIR 降格 (`ulisp/frontend_c/lower_to_lir.scm`)
1. **Managed Dialect 完全バイパス ＆ 呼び出し規約**:
   - `(c99-lower-to-lir typed-ast)` は GC セーフポイント・タグ付きポインタ命令（`%alloc-pair` 等）を一切出力せず、Core Machine LIR（`%add`, `%sub`, `%mul`, `%sdiv`, `%udiv`, `%srem`, `%urem`, `%and`, `%or`, `%xor`, `%shl`, `%ashr`, `%lshr`, `%icmp-*`, `%sext`, `%zext`, `%trunc`, `%alloca`, `%load`, `%store`, `%call`）のみを生成。
   - 全 C 関数定義および外部シンボル参照へ `calling-convention: 'sysv`（[calling_convention.scm](../../ulisp/compiler/calling_convention.scm)）を設定。
2. **ローカル変数・制御フロー・定数配置**:
   - ローカル変数および仮引数を `%alloca` として確保し、`Pass 132 Braun SSA`（[132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm)）に SSA レジスタ昇格を委ねる。
   - 短絡評価 `&&` / `||`、条件演算子 `?:`、`if`/`while`/`for`/`do-while`/`break`/`continue`/`return` を基本ブロック ＆ `%branch-if` / `%jump` へ展開し、文字列リテラルを `.rodata` 定数テーブルへ配置する。
3. **診断コード体系 (`diagnostic.scm` #833)**:
   - `"C99-SEMA-001"`（未宣言識別子・重複定義）、`"C99-SEMA-002"`（不正な左辺値への代入）、`"C99-SEMA-003"`（型不整合・返却型違反）、`"C99-SEMA-004"`（関数引数の個数・型不一致）、`"C99-SEMA-005"`（無効な定数式/0除算）。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `lower_to_lir.scm` が Managed Dialect 命令を一切出力せず、`lir_verifier.scm`（#835 Core LIR 検証）を全件通過すること。
- [ ] 整数演算（符号付き/符号なし比較・ビット演算・除算剰余）、整数昇格、短絡評価、ループ、`fib` 再帰呼び出しが Reference VM（`lir_interpreter.scm` #834）上で正しく動作すること。
- [ ] 不正な型代入・未宣言識別子・非左辺値代入に対して `diagnostic.scm` による Span 付きエラー（`C99-SEMA-001..005`）が出力されること。
- [ ] `ulisp/tests/test_c99_int_lowering.scm` を作成し、`make -C ulisp test_c99_int_lowering` が全件 PASS すること。

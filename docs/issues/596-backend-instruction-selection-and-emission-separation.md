---
ID: 596
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] Backend層: define-language L_asm 導入による命令選択とコード生成の2段階分離 (ID: 596)

## 1. 概要 / Summary
現在の ULisp バックエンド（`backend/140_backend_x86_64.scm`, `backend/150_backend_aarch64.scm`, `backend/160_backend_c.scm`）は、LIR 命令を受け取って直接文字列（GNU アセンブリ形式または C99 ソーステキスト）を組み立てて出力している。
この一枚岩の構成には以下の課題がある：
1. **ターゲット依存のピープホール最適化が困難**: 文字列化された後に命令の融合や冗長命令削除を行うのは極めて複雑。
2. **網羅性検証の欠如**: LIR の全命令・オペランド形式がターゲット機械語へ正しくマップされているか、AST レベルで静的検査できない。

本 Issue では、各バックエンドにターゲット命令を抽象化した `define-language L_asm_x86` / `L_asm_aarch64` / `L_ast_c99` を導入し、**「命令選択（Instruction Selection: LIR → L_asm）」** と **「コード出力（Code Emission / Unparser: L_asm → テキスト）」** の 2 段階分離を実現する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/pipeline_architecture.md)
- **関連 Issue**:
  - Issue 569: Pass 141 x86 世代別コピー GC ルーチン & Pass 142 フリースタンディングランタイム
  - Issue 593: LIR層 `L_lir_canonical` の導入（Backend の入力言語）
  - 依存 Issue: Issue 593

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/backend/backend_lang.scm](../../ulisp/backend/backend_lang.scm) (新規: `L_asm_x86_64`, `L_asm_aarch64`, `L_ast_c99` 言語定義)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (命令選択とテキスト出力の分離)
- [ ] [ulisp/backend/143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm) (新規: x86 機械語ピープホール最適化)
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm) (`L_ast_c99` 経由への整理)
- [ ] [ulisp/tests/test_backend_x86.scm](../../ulisp/tests/test_backend_x86.scm) (単体テスト)
- [ ] [ulisp/tests/test_c_backend.scm](../../ulisp/tests/test_c_backend.scm) (単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/596-backend-instruction-selection-and-emission-separation`

1. **ターゲット機械語 DSL `L_asm_x86` の定義 (`backend/backend_lang.scm`)**:
   - `x86_Opcode`: `movq`, `addq`, `subq`, `cmpq`, `jmp`, `jcc`, `call`, `ret`, `pushq`, `popq`, `leaq` 等
   - `x86_Operand`: 物理レジスタ `(%reg rax)`, 間接参照 `(%disp 8 (%reg rbp))`, 即値 `(%imm 123)`
   - `x86_Inst`: `(opcode opnd1 ...)`
2. **命令選択パス (`define-pass select-instructions-x86 : L_lir_canonical -> L_asm_x86`)**:
   - LIR 命令（例: `(%mov (%stack -8) %rax)`）をターゲット命令 S 式（例: `(movq (reg rax) (disp -8 (reg rbp)))`）へ純粋変換。
3. **ターゲット依存ピープホール最適化 (`143_backend_x86_peephole.scm`)**:
   - `((movq x y) (movq y x))` の削除
   - `(addq (imm 1) reg)` → `(incq reg)` への置換
4. **Unparser（テキストシリアライザ）の独立化**:
   - `L_asm_x86` の S 式を受け取り、フォーマットされたアセンブリ文字列を `display` する軽量シリアライザに特化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `define-language L_asm_x86` が定義され、x86 命令選択が中間 AST を介して行われること。
- [ ] 命令選択パスにより、未対応の LIR オペコードが存在した場合はコンパイル時に検知されること。
- [ ] 生成されるアセンブリ出力が既存のコンパイル結果と同一の動作セマンティクスを維持すること。
- [ ] `make test_unit`, `bash ulisp/test.sh`, `bash ulisp/test_c.sh` が 100% PASS すること。
- [ ] 生成バイナリの実行結果・性能テストにおいてリグレッションがないこと。

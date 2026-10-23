---
ID: 593
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合 (ID: 593)

## 1. 概要 / Summary
Issue 589（Canonical LIR 境界の確立）および Issue 590（物理層分離）により LIR 層が独立したが、現在の LIR 境界検証（`ulisp/lir/lir_verifier.scm`）は約 550 行の手続き型コードでハードコードされており、DSL（Nanopass Framework）の `define-language` による形式文法定義が存在しない。
これにより、LIR の構文仕様の変更とバリデータの挙動に乖離（Spec Drift）が発生するリスクがある。

本 Issue では、LIR 層の正典表現を Nanopass DSL として形式化した `define-language L_lir_canonical` を定義し、`lir/lir_verifier.scm` の判定ロジックと宣言的に統合・同期させる。これにより、LIR 境界における AST 検証を機械的に担保する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/pipeline_architecture.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/lir_specification.md)
- **関連 Issue**:
  - Issue 589: Canonical LIR 境界の確立
  - Issue 590: 3層物理ディレクトリ分離
  - 依存 Issue: なし（本ロードマップの第1ステップ）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) (Nanopass DSL コア: シーケンス・フラット命令列パターン対応の確認)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (LIR プログラム生成コア)
- [ ] [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm) (`L_lir_canonical` との整合性統合)
- [ ] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm) (新規: `L_lir_canonical` の言語定義)
- [ ] [ulisp/tests/test_lir_verifier.scm](../../ulisp/tests/test_lir_verifier.scm) (単体テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/593-define-lir-canonical-language-and-verifier-integration`

1. **`L_lir_canonical` の文法定義策定 (`ulisp/lir/lir_lang.scm`)**:
   - `L_lir_canonical` の Nonterminal 定義:
     - `Register`: `%rax`, `%rbx`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%rbp`, `%rsp`, `%r8`〜`%r15`, `%al`
     - `LValue`: Register, Stack (`(%stack offset)`), Memory (`(%mem base offset/index)`), Variable Symbol
     - `Operand`: LValue, Immediate Integer, Label Symbol
     - `Inst`: `%mov`, `%binop`, `%jump`, `%jump-cond`, `%label`, `%safepoint`, `%alloc`, `%call`, `%ret` 等
     - `Block`: 基本ブロック形式 `(%block label (arg ...) inst ...)`
     - `Function`: `(%function name (param ...) entry body ...)`
     - `Program`: `(%lir-program (function ...) body)`
2. **`lir_verifier.scm` との統合**:
   - `nanopass-ast-valid? 'L_lir_canonical expr` を `validate-lir` の第1段検証として組み込み、文法構造の不整合を瞬時に捕捉。
   - レジスタ割り当てや Safepoint アライメントなどの意味論的検証と責務を明確に分離。
3. **境界テストケースの実装**:
   - 正しい LIR および意図的に壊した不正な LIR（未登録命令、不正オペランド）に対する検証テストを `test_lir_verifier.scm` に拡充。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `ulisp/lir/lir_lang.scm` に `define-language L_lir_canonical` が形式定義されていること。
- [ ] `validate-lir` が `L_lir_canonical` 述語を透過的に活用し、正当な全 LIR 出力を 100% PASS すること。
- [ ] 不正なオペランドや未定義命令を含む LIR に対し、明瞭なエラーメッセージを伴って Fail-Fast すること。
- [ ] `make test_unit` および `bash ulisp/test.sh` が 100% PASS すること。
- [ ] 既存のパイプライン（`compile-to-lir`）の実行結果にリグレッションがないこと。

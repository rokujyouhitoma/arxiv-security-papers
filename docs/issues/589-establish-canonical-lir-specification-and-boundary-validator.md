---
ID: 589
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] LIR (Low-level IR) 仕様の厳格化と不変条件バリデータ導入によるフロントエンド・バックエンド境界の確立 (ID: 589)

## 1. 概要 / Summary

現在、ULisp コンパイラ内部において、高水準 S 式変換（Nanopass DSL、マクロ展開、脱糖、型推論、クロージャ変換等）と低水準コード生成（x86-64 / AArch64 / C99 アセンブリ出力、レジスタ割付、ABI）が単一の直列パイプラインに同居している。

本 Issue では、メタコンパイラ層（フロントエンド・ミドルエンド）とマシン語生成層（バックエンド）の完全分離の第 1 段階として、両層の接合部である **LIR (Low-Level Intermediate Representation)** を公式の公開中間仕様（Canonical LIR）として厳格化・標準化し、LIR 不変条件を機械的に検証する独立バリデータ（`validate-lir` / LIR Verifier）を導入する。

これにより、高水準言語層の出力契約（Contract）を固定し、後続の物理層分離（Issue 590）およびテスト階層化（Issue 591）のための強固な境界基盤を確立する。

---

## 2. トレーサビリティ / Traceability

- **アーキテクチャ仕様**:
  - DSN-33 コンパイラアーキテクチャ仕様書
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)
  - [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md)
- **関連 Issue**:
  - [583-nanopass-decomposition-of-lir-pass-130.md](closed/583-nanopass-decomposition-of-lir-pass-130.md) (LIR Nanopass 分割)
  - [576-implement-lightweight-ir-verifier-framework.md](closed/576-implement-lightweight-ir-verifier-framework.md) (軽量 IR Verifier)
  - [587-extract-dsl-expansion-pass-before-macro-expander.md](closed/587-extract-dsl-expansion-pass-before-macro-expander.md) (Pass 015 Nanopass DSL 先行展開)
  - Issue 590 (ULisp コンパイラ層の物理分離)
  - Issue 591 (コンパイラドライバおよびテストスイートの階層化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md) (Canonical LIR 正典仕様の策定・更新)
- [ ] [ulisp/compiler/lir_verifier.scm](../../ulisp/compiler/lir_verifier.scm) (新規: LIR 構文・オペランド・SSA 不変条件バリデータ)
- [ ] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm) (LIR 生成後の Verifier 呼び出しフック整備)
- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (LIR 出力境界でのバリデーション結線)
- [ ] [ulisp/tests/test_lir_verifier.scm](../../ulisp/tests/test_lir_verifier.scm) (新規: LIR バリデータ単体テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (テストターゲットおよびビルド依存の更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/589-establish-canonical-lir-specification-and-boundary-validator`

1. **Canonical LIR 文法仕様の定義**:
   - 3番地命令形式、オペランド種別（即値、レジスタ、スタックスロット、ラベル）、関数定義形式（`%function` / `%closure`）の厳格な BNF 仕様を [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md) に定義。
2. **LIR Verifier (`ulisp/compiler/lir_verifier.scm`) の新設**:
   - 不正なオペランド、未定義ラベル、重複ラベル、不正な制御フロー命令を検出する述語群（`lir-valid-inst?`, `lir-valid-operand?`）の実装。
   - デバッグモード (`DEBUG=1` または `--verify-lir`) で LIR 生成直後に全ノードを走査し、不変条件違反時に詳細な診断メッセージを報告する機構。
3. **境界テストスイートの構築**:
   - 正しい LIR および意図的に壊した LIR に対する Verifier 単体テストの作成。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] Canonical LIR の文法・不変条件仕様書が更新されていること。
- [ ] LIR Verifier が実装され、既存の全 42+ テストのコンパイル時に LIR バリデーションが 100% PASS すること。
- [ ] 不正な LIR 命令（例: 不正な型タグ、壊れたジャンプラベル）を検出して適切なエラーを出力する単体テストが PASS すること。
- [ ] `make test`, `make test_c` を含む品質ゲートが全て正常完了すること。

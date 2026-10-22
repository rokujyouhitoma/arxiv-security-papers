---
ID: 589
種別: Feature
優先度: High
ステータス: Closed
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
  - [586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md](closed/586-nanopass-framework-phase4-pipeline-observability-diff-trace-and-verifier-hooks.md) (Nanopass Phase 4: AST Diff & Verifier Hooks)
  - Issue 590 (ULisp コンパイラ層の物理分離)
  - Issue 591 (コンパイラドライバおよびテストスイートの階層化)

---

## 3. セキュリティ・脅威分析 / Threat Analysis & Security Considerations

- **脅威ベクトル 1: 構造不正な命令・不正オペランドによるバックエンドでのコード生成汚染**
  - 未検証の命令形状や未知のオペコードがバックエンドに渡った場合、C バックエンドでのフォーマット不整合、不正なアセンブリ命令の生成、予期しないコード実行を引き起こす危険がある。
  - **対策**: 全オペコード（60+種）およびオペランド（レジスタ名、即値境界、メモリオフセット、スタックスロット）に対する厳格な型・構文検査を実施。
- **脅威ベクトル 2: ラベル重複および未定義ジャンプ先による制御フロー破壊**
  - 同一関数内でのラベル重複定義や、存在しないラベルへのジャンプは、不正な基本ブロック遷移やリターンアドレス破壊を引き起こす。
  - **対策**: 関数スコープ単位でのラベル一意性検査およびジャンプ先ラベルの存在確認（CFG Closure 検査）を機械的に実施。
- **脅威ベクトル 3: スタックフレーム長不整合によるメモリ破損**
  - `frame-size` が負数または 8 バイト境界（16 バイト ABI アライメント）に沿っていない場合、スタックポインタが破壊され、リターンアドレスの不正上書きや GC スタック走査での SEGV が発生する。
  - **対策**: `frame-size` が非負かつ 8 の倍数（偶数アライメント）であることをバリデータで強制。
- **脅威ベクトル 4: 基本ブロック引数 (Block Arguments) の引数・仮引数不一致**
  - SSA ブロック定義のパラメータ数と `%jump` / `%jump-if` の引数リストの長さが食い違っている場合、平行代入ルーチンが不完全となり未初期化レジスタ参照が生じる。
  - **対策**: 基本ブロック定義仮引数リスト長とジャンプ命令の実引数リスト長の一致をバリデータで検証。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md) (Canonical LIR 正典仕様の策定・更新: BNF文法、オペコード辞書、不変条件の明文化)
- [x] [ulisp/compiler/lir_verifier.scm](../../ulisp/compiler/lir_verifier.scm) (新規: LIR 構文・オペランド・CFG/SSA 不変条件バリデータ `validate-lir` / `verify-lir`)
- [x] [ulisp/compiler/verifier.scm](../../ulisp/compiler/verifier.scm) (統合 Verifier との結線: `verify-pass-output 'lir`)
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (LIR 出力境界でのバリデーション結線: `verify-mode` 時に `validate-lir` 実行)
- [x] [ulisp/tests/test_lir_verifier.scm](../../ulisp/tests/test_lir_verifier.scm) (新規: LIR バリデータ単体テストスイート - 正常系・各種異常系拒絕網羅)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`COMPILER_BASE` への `compiler/lir_verifier.scm` 追加、`test_lir_verifier` ターゲット新設、テスト連動)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/589-establish-canonical-lir-specification-and-boundary-validator`

1. **Canonical LIR 文法仕様の定義 (`ulisp/docs/lir_specification.md`)**:
   - `%lir-program` ルート仕様（`strings`, `stackmaps`, `%lir-functions`, `%lir-main`）の厳格 BNF。
   - `%lir-function` および `%lir-main` の構造仕様（`frame-size`, `params`, `body`）。
   - 全 Canonical オペコード（制御フロー、関数呼出/ABI、データ転送/メモリ、算術/論理/ビット演算、ランタイム/GC、例外/多値/継続）の許容オペランド定義。
   - レジスタセット（`%rax`..`%r15`, `%al`）およびメモリオペランド形式（`(%reg ...)`, `(%stack ...)`, `(%mem ...)`）の定義。

2. **LIR Verifier (`ulisp/compiler/lir_verifier.scm`) の新設**:
   - `(validate-lir prog)` / `(verify-lir prog)` の実装。
   - 下位述語群の実装:
     - `lir-valid-register?`: 許容レジスタ集合の検証。
     - `lir-valid-operand?`: 即値、レジスタ、スタックスロット、メモリオペランドの適合性。
     - `lir-valid-inst?`: 各命令オペコードごとの arity および各引数の型・位置検証。
     - `lir-valid-function?`: 各関数の `label`, `params`, `frame-size`, `body` 形式検証。
     - `lir-valid-cfg?`: 関数内ラベルの一意性、ジャンプ先端ラベルの存在、および `%block` 引数アリティの一致検証。
   - エラーハンドリング:
     - `verifier-error` を通じたコンテキスト付き警告（非 strict モード時は `#f` 返却、strict モード時は例外 raise）。

3. **コンパイラドライバおよび統合 Verifier への統合**:
   - `ulisp/compiler/verifier.scm`: `verify-pass-output 'lir` または `'ssa` から `verify-lir` を呼び出し可能にする。
   - `ulisp/compiler/driver.scm`: Pass 130 実行直後、バックエンドへ引き渡す直前に `(if verify-mode (verify-lir lir130) #t)` を実行。

4. **単体テストスイートの構築 (`ulisp/tests/test_lir_verifier.scm`)**:
   - 正常系テスト: 典型的な LIR プログラム（算術、関数定義、ブロック引数付きループ、継続、例外、多値）が `validate-lir` を PASS すること。
   - 異常系テスト:
     - ルートノード不正（`%lir-program` 欠落、`%lir-main` 欠落）
     - 未知のオペコードの拒絶
     - 不正なレジスタ名、不正なメモリオペランド形式の拒絶
     - アライメント違反の `frame-size`（8 の倍数でない、負数）の拒絶
     - 同一関数内での重複ラベルの拒絶
     - 存在しないラベルへのジャンプ（未解決ラベル）の拒絶
     - `%block` パラメータ数と `%jump` 実引数リストの要素数不一致の拒絶

5. **Makefile 依存関係の更新と既存テスト検証**:
   - `COMPILER_BASE` に `compiler/lir_verifier.scm` を登録。
   - `test_lir_verifier` ターゲットを追加。
   - 既存全 33 Nanopass テストおよび 139 C バックエンドテストを実行し、100% PASS を確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/docs/lir_specification.md` が Canonical LIR の完全な仕様書として更新されていること。
- [x] `ulisp/compiler/lir_verifier.scm` が作成され、LIR 構文・オペランド・CFG・SSA の全不変条件を検証できること。
- [x] `ulisp/tests/test_lir_verifier.scm` が作成され、正常系および全異常系テストが 100% PASS すること。
- [x] `ulisp/compiler/driver.scm` および `ulisp/compiler/verifier.scm` にバリデータが統合されていること。
- [x] `make -C ulisp test_verifier`, `make -C ulisp test_lir_verifier`, `make -C ulisp test_all_passes`, `make -C ulisp test_c` がすべてエラーゼロで完了すること。
- [x] 相対パス規則・OKF v0.2 品質基準に違反がないこと。

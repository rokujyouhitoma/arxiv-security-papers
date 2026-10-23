---
ID: 591
種別: Feature
優先度: Medium
ステータス: Closed (2026-10-23)
---

# [FEAT/ENH] コンパイラドライバおよびテストスイートの階層化（LIR中間出力モード `--target-lir` およびフロントエンド／バックエンド独立検証基盤の構築） (ID: 591)

## 1. 概要 / Summary

Issue 589（Canonical LIR 境界の確立）および Issue 590（物理層分離）により、ULisp コンパイラ内部の構造的分離（`frontend/` と `backend/`）が完了した。

本 Issue では、この分離構造を外部インターフェースおよびテスト体系に完全に反映させるため、コンパイラドライバに **LIR 中間出力・停止モード（`--target-lir` / `(!target lir)`）** を新設する。
（※ 命名の直交性を保つため、別系統の語彙となる `--emit-lir` 等の冗長なエイリアスは導入せず、ターゲット体系に準拠した `--target-lir` に一本化する。）
また、コンパイラドライバが Canonical LIR S 式（`(%lir-program ...)`）を直接入力として受け取り、フロントエンドをバイパスしてバックエンドのみを実行できる **LIR 直接入力モード（Direct LIR Mode）** を実装する。

これにより、テストスイートを以下の 2 層に階層化・独立化する：
1. **Frontend 単体テスト（Scheme $\to$ LIR S式）**: C コンパイラやアセンブラを起動せず、純粋な記号処理として数ミリ秒で高速実行可能な回帰テスト（Fast-Fail）。
2. **Backend 単体テスト（LIR S式 $\to$ Asm/C/バイナリ実行）**: フロントエンドの仕様変更や脱糖の影響を完全に遮断し、固定された LIR フィクスチャからバックエンドのコード生成・最適化を高精度に検証。

---

## 2. トレーサビリティ / Traceability

- **アーキテクチャ仕様**:
  - [DSN-33 コンパイラアーキテクチャ仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md) (3層物理分離および中間言語仕様)
  - [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md) (Canonical LIR 命令仕様)
  - [ulisp/docs/testing_guide.md](../../ulisp/docs/testing_guide.md) (テスト実行ガイド)
- **関連 Issue**:
  - Issue 589: Canonical LIR 仕様とバリデータ (`lir_verifier.scm`)
  - Issue 590: ULisp コンパイラ層の物理分離 (`frontend/`, `lir/`, `backend/`)
  - Issue 593: LIR層 `define-language L_lir_canonical` の導入
  - [572-unify-pass-tests-to-one-to-one-mapping-with-ulisp-passes.md](closed/572-unify-pass-tests-to-one-to-one-mapping-with-ulisp-passes.md) (パステストの 1:1 整合化)
  - [526-mytkowicz-bias-elimination.md](closed/526-mytkowicz-bias-elimination.md) (差分テストフレームワーク)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`--target-lir` および `(!target lir)` の解釈、および `(%lir-program ...)` 直接入力バイパスの実装)
- [x] [ulisp/test_lir.sh](../../ulisp/test_lir.sh) (新規: フロントエンド LIR スナップショット・回帰テストスイート)
- [x] [ulisp/test_backend.sh](../../ulisp/test_backend.sh) (新規: LIR フィクスチャ入力からのバックエンド直接検証テストスイート)
- [x] [ulisp/tests/fixtures/lir/01_const_int.lir](../../ulisp/tests/fixtures/lir/01_const_int.lir) (新規: バックエンド検証用 LIR フィクスチャ)
- [x] [ulisp/tests/fixtures/lir/02_add.lir](../../ulisp/tests/fixtures/lir/02_add.lir) (新規: バックエンド検証用 LIR フィクスチャ)
- [x] [ulisp/tests/fixtures/lir/03_branch.lir](../../ulisp/tests/fixtures/lir/03_branch.lir) (新規: バックエンド検証用 LIR フィクスチャ)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`make test_lir_suite`, `make test_backend`, `make test_hierarchical` ターゲットの追加)
- [x] [ulisp/docs/testing_guide.md](../../ulisp/docs/testing_guide.md) (階層化テスト体系と LIR モードの利用ガイド更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/591-hierarchical-compiler-driver-and-test-suites`

### 4.1 CLI オプションおよびディレクティブ設計
- **`--target-lir` への一本化**:
  - `--gc-stress` や `--trace-passes` 等の既存 CLI フラグシンボルに合わせ、CLI 引数およびストリーム先頭シンボルとして `--target-lir` をファーストクラスにサポート。
  - S式ソース内ディレクティブとしては、既存の `(!target x86_64)`, `(!target c)` と完全に対称となる `(!target lir)` を受理。
  - 語彙の拡散とドキュメントのブレを防ぐため、`--emit-lir` 等の別系統エイリアスは導入しない。
- **Direct LIR Ingestion（LIR 直接入力モード）**:
  - 入力フォームの先頭（ディレクティブ除去後）が `(%lir-program ...)` である場合、ドライバは `compile-to-lir`（Frontend 全パス）をスキップし、`validate-lir` を実行した上で直接 `compile-backend` に渡す。

### 4.2 ドライバ (`compiler/driver.scm`) の更新
1. `extract-directives-and-forms`:
   ```scheme
   ((or (eq? first '--target-lir)
        (and (pair? first) (eq? (car first) '!target) (eq? (cadr first) 'lir)))
    (loop (cdr forms) 'lir gc-mode verify trace))
   ```
2. エントリポイント制御:
   ```scheme
   (cond
     ((eq? target 'lir)
      ;; Frontend 実行後、LIR を Pretty-Print / Dump して正常終了
      (let ((lir (compile-to-lir forms verify-mode trace-mode)))
        (dump-lir-ast lir)))
     ((and (pair? forms) (pair? (car forms)) (eq? (caar forms) '%lir-program))
      ;; Direct LIR Mode: Frontend をバイパスして Backend のみ実行
      (let ((lir (car forms)))
        (if verify-mode
            (begin
              (enable-verifier!)
              (verify-pass-output 'lir lir)))
        (compile-backend lir target gc-mode)))
     (else
      ;; 通常のフルパイプライン (Frontend -> LIR -> Backend)
      (let ((lir (compile-to-lir forms verify-mode trace-mode)))
        (compile-backend lir target gc-mode))))
   ```

### 4.3 階層化テストスイートの構築
1. **`ulisp/test_lir.sh` (Frontend 単体テスト)**:
   - 基本構文、マクロ、多値、クロージャ、継続、例外、動的スコープなどの Scheme ソースを `ulisp --target-lir` に通し、出力された LIR S 式が期待される正規化構造（`tests/golden/lir/*.lir`）と一致するかを `diff` 検証。
   - gcc/as/実行バイナリを伴わないため、数百ケースの回帰テストを 1 秒以内で高速完走。
2. **`ulisp/test_backend.sh` (Backend 単体テスト)**:
   - レジスタ割り当て、呼出規約、スタックアロケーション、分岐比較、64ビット算術、Safepoint を含む Canonical LIR フィクスチャ（`tests/fixtures/lir/*.lir`）を用意。
   - `cat fixture.lir | ulisp --target x86_64` および `ulisp --target c` でコード生成し、ネイティブ実行結果の返り値と出力を検証。
3. **Makefile ターゲットの整備**:
   - `make test_lir_suite`: フロントエンド単体テストの高速実行。
   - `make test_backend`: バックエンド単体テストの実行。
   - `make test_hierarchical`: `test_lir_suite` $\to$ `test_backend` $\to$ `test.sh` (E2E) の順序で実行する階層テスト。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `--target-lir`（および `(!target lir)`）を指定した際に、Pass 130（および Pass 131/132）通過後の Canonical LIR S 式が標準出力へ整形出力され、終了コード 0 で正常終了すること。
- [x] `(%lir-program ...)` を標準入力に直接流し込んだ場合、フロントエンドをスキップしてバックエンドコード生成が正常に動作すること。
- [x] `ulisp/test_lir.sh` が新設され、フロントエンドの主要全機能（即値、算術、局所変数、クロージャ、継続、マクロ、多値）の LIR 出力が外部ツールチェイン非依存で高速に PASS すること。
- [x] `ulisp/test_backend.sh` が新設され、固定 LIR フィクスチャからの x86-64 / C99 バックエンド生成バイナリの動作が PASS すること。
- [x] `Makefile` に `test_lir_suite`, `test_backend`, `test_hierarchical` が組み込まれ、既存の `test.sh`, `test_c.sh` および 3-Stage ブートストラップに一切のリグレッションがないこと。
- [x] `ulisp/docs/testing_guide.md` に、階層化テストの実行方法（開発サイクルにおける `make test_lir_suite` による高速フィードバック手法）が文書化されていること。

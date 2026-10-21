---
ID: 591
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] コンパイラドライバおよびテストスイートの階層化（LIR中間出力モードおよびフロントエンド／バックエンド独立検証基盤の構築） (ID: 591)

## 1. 概要 / Summary

Issue 589（Canonical LIR 境界の確立）および Issue 590（物理層分離）により、ULisp コンパイラ内部の構造的分離が完了する。

本 Issue では、この 2 層分離構造を外部インターフェースおよびテスト体系に完全に反映させるため、コンパイラドライバに **LIR 中間出力モード（`--emit-lir` / `(!target lir)`）** を新設し、テストスイートを「**Frontend 単体テスト（Scheme $\to$ LIR）**」と「**Backend 単体テスト（LIR $\to$ Asm/C）**」に階層化・独立化する。

これにより、フロントエンドの記号処理テストをアセンブラや C コンパイラを介さずミリ秒単位で高速実行可能にし、バックエンドの最適化も固定された LIR 入力からの差分テストとして高精度に実施できるようにする。

---

## 2. トレーサビリティ / Traceability

- **アーキテクチャ仕様**:
  - DSN-33 コンパイラアーキテクチャ仕様書
  - [ulisp/docs/testing_guide.md](../../ulisp/docs/testing_guide.md)
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)
- **関連 Issue**:
  - Issue 589 (Canonical LIR 仕様とバリデータ)
  - Issue 590 (ULisp コンパイラ層の物理分離)
  - [572-unify-pass-tests-to-one-to-one-mapping-with-ulisp-passes.md](closed/572-unify-pass-tests-to-one-to-one-mapping-with-ulisp-passes.md) (パステストの 1:1 整合化)
  - [526-mytkowicz-bias-elimination.md](closed/526-mytkowicz-bias-elimination.md) (差分テストフレームワーク)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`(!target lir)` および `--emit-lir` オプションの実装)
- [ ] [ulisp/test_lir.sh](../../ulisp/test_lir.sh) (新規: フロントエンド LIR スナップショット・回帰テストスイート)
- [ ] [ulisp/test_backend.sh](../../ulisp/test_backend.sh) (新規: LIR 入力からのバックエンド直接検証テスト)
- [ ] [ulisp/Makefile](../../ulisp/Makefile) (`make test_lir`, `make test_backend` ターゲットの追加)
- [ ] [ulisp/docs/testing_guide.md](../../ulisp/docs/testing_guide.md) (階層化テスト体系の記述更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/591-hierarchical-compiler-driver-and-test-suites`

1. **ドライバへの LIR 停止オプションの追加**:
   - `(!target lir)` ディレクティブまたは CLI 引数 `--emit-lir` を指定された場合、Pass 130（および Pass 131/132 SSA/Verifier）の完了時点で LIR S 式を出力して正常終了する。
2. **Frontend LIR ゴールデンテスト基盤の構築**:
   - 代表的な Scheme 式（即値、算術、局所変数、クロージャ、継続、マクロ、多値）について、生成される LIR S 式の構造的一致を高速に検証するテストスイート（`test_lir.sh`）を導入。
3. **Backend LIR フィクスチャ駆動テストの構築**:
   - 固定された LIR S 式を入力ファイルとして与え、x86-64 / C99 バックエンドが正しくコンパイルおよび実行できることを検証するテストスイート（`test_backend.sh`）を導入。
4. **CI および Makefile 統合**:
   - `make test` の前段階として高速な `make test_lir` を実行し、早期失敗（Fast-Fail）フィードバックを実現。

---

## 5. 完了条件 / Success Criteria (DoD)

- [ ] `(!target lir)` を指定した際に、整形された Canonical LIR が標準出力へ正しくダンプされること。
- [ ] `make test_lir` が導入され、フロントエンドの主要機能が外部コンパイラ非依存で高速に PASS すること。
- [ ] 従来の E2E テスト（`test.sh`, `test_c.sh`）およびブートストラップが一切の回帰なく動作すること。
- [ ] `docs/testing_guide.md` に階層化テストの実行方法と設計思想が明記されていること。

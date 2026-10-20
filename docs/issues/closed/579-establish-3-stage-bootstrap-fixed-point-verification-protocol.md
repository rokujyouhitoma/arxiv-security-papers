---
ID: 579
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/CI] 3-Stage Bootstrap の固定点（Fixed-Point）自動検証プロトコルの確立 (ID: 579)

## 1. 概要 / Summary
uLisp は自己記述型コンパイラとして `ulisp/bootstrap.sh` や `bin/ulisp-boot` を備えている。しかし、META II や Nanopass、CompCert などの先行研究が示す「完全な自己ホスト（Self-hosting）」の成立条件である「固定点到達（Fixed-Point Convergence: Stage 2 と Stage 3 の生成物が完全一致すること）」の機械的・決定論的検証プロトコルが自動化されていなかった。

本 Issue では、Stage 0（ホスト環境: Python `ilisp` または外部 Scheme）から Stage 1（第1世代コンパイラ）、Stage 2（第2世代コンパイラ）、Stage 3（第3世代コンパイラ）を逐次ビルドし、Stage 2 で出力された C コードと Stage 3 で出力された C コードの差分が完全 0 バイトであることを自動検証する `make bootstrap_verify` ターゲットおよび検証スクリプトを構築する。これにより、コンパイラ自身の変換における自己閉包性と意味保存性を決定論的に保証する。

---

## 2. トレーサビリティ / Traceability
- 先行研究系譜: META II 自律ブートストラップ思想 (Val Schorre, 1964)
- 先行研究系譜: Reproducible Builds and Bootstrapping (CakeML, Guix Bootstrapping)
- DSN-33 アーキテクチャ仕様
- 関連 Issue:
  - [closed/541-implement-fast-bootstrap-seed-and-subsecond-build-pipeline.md](closed/541-implement-fast-bootstrap-seed-and-subsecond-build-pipeline.md)
  - [closed/552-fix-unbound-variable-car-in-lir-bootstrap.md](closed/552-fix-unbound-variable-car-in-lir-bootstrap.md)
- 関連ファイル:
  - [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh)
  - [ulisp/Makefile](../../ulisp/Makefile)
  - [ulisp/compiler.scm](../../ulisp/compiler.scm)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (Stage 1 / Stage 2 / Stage 3 の生成および diff 自動判定プロトコルの追加)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`bootstrap_stage1`, `bootstrap_stage2`, `bootstrap_stage3`, `bootstrap_verify` ターゲット追加)
- [x] [ulisp/docs/bootstrap.md](../../ulisp/docs/bootstrap.md) (新規または更新: 3-Stage Bootstrap の数学的背景・再現可能性手順の文書化)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/579-establish-3-stage-bootstrap-fixed-point-verification-protocol`

1. **3-Stage ビルドパイプラインの定義 (`ulisp/bootstrap.sh`)**:
   - **Stage 0 → Stage 1**:
     - ホストエンジン（`$(RUN_SCHEME) compiler.scm`）で `compiler.scm` をコンパイルし、`build/stage1_compiler.c` を生成。
     - `gcc` でコンパイルして実行可能バイナリ `build/ulisp-stage1` を作成。
   - **Stage 1 → Stage 2**:
     - `build/ulisp-stage1` を実行エンジンとして `compiler.scm` をコンパイルし、`build/stage2_compiler.c` を生成。
     - `gcc` でコンパイルして実行可能バイナリ `build/ulisp-stage2` を作成。
   - **Stage 2 → Stage 3**:
     - `build/ulisp-stage2` を実行エンジンとして `compiler.scm` をコンパイルし、`build/stage3_compiler.c` を生成。
2. **固定点判定（Fixed-Point Diff Validation）**:
   - `diff -u build/stage2_compiler.c build/stage3_compiler.c` を実行。
   - 差分が 0 行であれば「固定点到達（Fixed-Point Achieved）」として終了コード 0 を返却。
   - 差分が存在する場合は、不一致行をカラー出力してエラーコード 1 で中断。
3. **Makefile ターゲット統合**:
   - `make -C ulisp bootstrap_verify` を新設し、ワンコマンドで 3 世代ビルドと固定点検証を実行可能にする。
   - 成功時に生成された `build/ulisp-stage3` を `bin/ulisp-boot` へシードとして安全に反映するオプションを提供。
4. **仕様ドキュメント整備 (`ulisp/docs/bootstrap.md`)**:
   - ブートストラップサイクルの概念図、META II 的背景、トラブルシューティング手順を記録。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `bootstrap.sh` に 3-Stage ビルドおよび Stage 2 vs Stage 3 の diff 検証ロジックが組み込まれていること
- [x] `make -C ulisp bootstrap_verify` が正常に実行され、差分 0 バイト（固定点到達）が確認できること
- [x] 生成された自己ホストバイナリが全テストスイート（`test_all_passes`, `test_aot`）を通過すること
- [x] ブートストラップ理論と検証手順が `ulisp/docs/` 内に文書化されていること
- [x] 相対パスのみを使用し、絶対パスが含まれないこと

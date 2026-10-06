---
ID: 493
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] ULisp Phase 7: 3段階セルフホスティングブートストラップ連鎖と不動点検証 (diff stage2.s stage3.s == 0) の実装 (ID: 493)

## 1. 概要 / Summary

[DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) に基づき、ULisp の最終フェーズである Phase 7（Step 25〜27: Stage 1〜Stage 3 の 3 段階ブートストラップ連鎖およびアセンブリ不動点検証）を実装する。

Abdulaziz Ghuloum 氏の論文および compilerbook の最終到達点として、ULisp で書かれたコンパイラ自身（`compiler.scm`）をコンパイルしてネイティブバイナリ `scheme-stage1` を生成し、そのネイティブバイナリがさらに自分自身をコンパイルして `scheme-stage2` を生成し、最後に生成された `stage2.s` と `stage3.s` が 1 バイトの狂いもなく完全一致（`diff stage2.s stage3.s` 差分ゼロ）することを実証する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [DSN-33: ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 4 章 Phase 7, 第 5 章 3段階セルフホスティングブートストラップ連鎖と不動点検証, 第 8 章 テスト設計)
  - [DSN-31: ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md) (第 5 章 Backend B: Native AOT コンパイラ結合)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (自己充足的コンパイラ構造、自前 `read` の統合または標準 S 式シーケンスコンパイル)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (Stage 1 $\to$ Stage 2 $\to$ Stage 3 自動ビルドおよび `diff` 不動点検証スクリプト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`make bootstrap` ターゲットの追加)
- [x] [ulisp/README.md](../../ulisp/README.md) (ロードマップ進捗状況表の更新: Phase 7 完了、ULisp 全工程完遂)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳更新)

---

## 4. 実装方針 / Implementation Plan

Target Branch: `feat/493-implement-ulisp-phase7-self-hosting-bootstrap-and-fixed-point`

1. **コンパイラの自己充足化 (Step 25)**:
   - `compiler.scm` が自身のサポートする構文（`letrec`, `lambda`, `if`, `cond`, `let`, `let*`, `cons`, `car`, `cdr`, `pair?`, `eq?`, `read-char`, `write-char`, `peek-char`, `eof-object?`, 四則演算、比較演算）のみで動作するように整合性を担保。
   - 複数 S 式のプログラムコンパイルループ、または単一の自己完結型プログラムとしてのパッケージング。
2. **ブートストラップ連鎖の構築 (Step 26)**:
   - **Stage 1**: ホスト処理系（`python3 -m ilisp`）で `compiler.scm` を実行し、`compiler.scm` をコンパイル $\to$ `stage1.s` $\to$ `gcc -no-pie stage1.s runtime.c -o scheme-stage1`。
   - **Stage 2**: `./scheme-stage1 < compiler.scm > stage2.s` $\to$ `gcc -no-pie stage2.s runtime.c -o scheme-stage2`。
   - **Stage 3**: `./scheme-stage2 < compiler.scm > stage3.s`。
3. **不動点検証 (Step 27 / Fixed-Point Verification)**:
   - `diff -u stage2.s stage3.s` を実行。
   - 決定論的コード生成（ラベル生成、シンボルインターン順序）により差分が 0 バイトであることを確認。
4. **自動化スクリプト (`bootstrap.sh`) と Makefile 統合**:
   - ワンコマンドで Stage 1〜3 を走らせ、`diff` 結果を判定してステータスコード 0 で終了するテストスクリプトを作成。

---

## 5. 完了条件 / Success Criteria (DoD)

- [x] `stage1.s`, `stage2.s`, `stage3.s` が正常に生成され、各ネイティブバイナリがエラーなくリンク・実行できること。
- [x] `diff stage2.s stage3.s` の終了コードが 0（差分ゼロ）であること。
- [x] 生成されたネイティブコンパイラ `scheme-stage2` がテストプログラム（42 や階乗など）を正常にコンパイルし、実行結果が一致すること。
- [x] `make -C ulisp bootstrap` が成功すること。
- [x] `ulisp/README.md` の進捗状況表で Phase 7 が完了として反映されること。

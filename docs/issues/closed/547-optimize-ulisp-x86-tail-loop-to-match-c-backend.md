---
ID: 547
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] ULisp x86における末尾再帰ループ (loop 10M) の高速化（ループヘッダ回転・直結バックワード分岐・アンローリング） (ID: 547)

## 1. 概要 / Summary
最新ベンチマーク実測において、ULisp x86 の末尾再帰ループ（`loop 10M`）は Issue #546（インプレース引数シャッフル）により 22.88 ms から **4.79 ms**（Chez Scheme 64.59 ms 比で約13.5倍高速）へと劇的に改善された。

しかしながら、Portable C バックエンド（GCC -O2 経由）の実測値 **0.59 ms** と比較すると約 8 倍の開きが存在する。この要因をマイクロアーキテクチャおよび生成アセンブリから分析したところ、以下の非効率性が判明した：
1. **条件判定の不要な Boolean オブジェクト化 (過剰型ボックス化)**:
   ループ先頭の `(if (= i 10000000) ...)` において、`cmp` 結果を `sete` で一旦 Scheme 真偽値（`#t` = 111, `#f` = 47）に変換してスタックに保存し、直後に再度読み出して `cmp rax, 0x2F; je .L_else` している（7命令およびメモリ往復）。
2. **スタック変数のメモリ往復 (レジスタ未固定)**:
   自己ホストブートストラップの安全性担保のため一時的にスタック渡しに倒していたが、外部呼び出しのない「リーフループ（Leaf Loop）」であれば、Callee-saved レジスタ（`%rbx`, `%r13`, `%r14`）に固定化し、プロローグ/エピローグで退避復元することでメモリアクセスを完全 0 化できる。
3. **二重ジャンプの存在（ループヘッダ反転・ローテーションの未適用）**:
   現状の x86 出力はループ先頭で `je .L_else`、末尾で無条件 `jmp .L_cont_entry` となっており、1反復あたり計2回の分岐命令を実行している。Do-While ループ回転を適用すれば、ループ末尾の単一バックワード条件分岐 `jne .L_loop_body` のみで反復可能となる。
4. **ループアンローリング（2x / 4x Multi-Accumulator Unrolling）**:
   演算の依存連鎖を複数アキュムレータで分離し、スーパースカラ CPU の ILP（命令レベル並列性）を最大化する。

本 Issue では、3 つの推奨着手ステップに従って段階的に実装し、ULisp x86 のループ実行性能を ULisp C（0.59 ms）と同等のサブミリ秒（real 0.00 / 0.58 ms）水準へと引き上げた。

---

## 2. トレーサビリティ / Traceability
- 実測ベンチマーク表: [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md) 第6章
- 関連Issue:
  - [closed/544-implement-loop-variable-register-allocation.md](closed/544-implement-loop-variable-register-allocation.md) (ループ変数レジスタ割付)
  - [closed/545-implement-condition-branch-flag-fusion.md](closed/545-implement-condition-branch-flag-fusion.md) (条件分岐融合)
  - [closed/546-implement-in-place-tail-loop-argument-shuffle-optimization.md](closed/546-implement-in-place-tail-loop-argument-shuffle-optimization.md) (インプレース末尾引数シャッフル)
  - [closed/552-fix-unbound-variable-car-in-lir-bootstrap.md](closed/552-fix-unbound-variable-car-in-lir-bootstrap.md) (ブートストラップ不動点到達)
- 測定スクリプト: [tools/benchmark_portable_guide.py](../../tools/benchmark_portable_guide.py)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (リーフ判定、比較分岐融合、ループ回転 LIR 最適化)
- [x] [ulisp/passes/07_backend_x86_64.scm](../../ulisp/passes/07_backend_x86_64.scm) (単一バックワード条件分岐への還元、レジスタ退避復元)
- [x] [ulisp/compiler.scm](../../ulisp/compiler.scm) (統合コンパイラ再生成)
- [x] [ulisp/test.sh](../../ulisp/test.sh) (回帰テストおよびブートストラップ検証)
- [x] [ulisp/bootstrap.sh](../../ulisp/bootstrap.sh) (不動点検証およびエラー表示改善)
- [x] [tools/benchmark_portable_guide.py](../../tools/benchmark_portable_guide.py) (性能検証スクリプト)
- [x] [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md) (測定結果更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/547-optimize-ulisp-x86-tail-loop-to-match-c-backend`

### Step 1: 条件分岐融合（Branch Fusion）の完全化
- `lir-compile-if` において、テスト式が `(= a b)` や `(< a b)` などの比較命令である場合、Boolean 値へのボクシング（`sete` + `add 0x2f`）をバイパスし、LIR レベルで直接 `%branch-if-not-equal` 等を出力する。
- 1反復から 5 命令および不要なメモリアクセスを排除。

### Step 2: リーフループ限定のレジスタ固定化 (Leaf Loop Register Pinning)
- `%cont-fun` 内に外部関数呼び出し（`call` / 非インライン式）が含まれないことを検査する述語 `cont-body-has-external-call?` を導入。
- 外部呼出がないリーフループの場合のみ、ループ変数を Callee-saved レジスタ（`%rbx`, `%r13`, `%r14`）に割り当てる。
- 当該関数のプロローグで Callee-saved レジスタをスタックに `push` し、エピローグで `pop` することで、ブートストラップコンパイラや上位の呼び出し規約を 100% 遵守。
- 反復ごとのスタックアクセスをゼロ化。

### Step 3: ループヘッダ回転 (Loop Rotation / Inversion)
- ループ先頭のガード条件を反転し、Do-While 構造へとブロックを再編成。
- ループ末尾の無条件ジャンプ `jmp .L_cont_entry` を排除し、単一のバックワード条件分岐 `jne .L_loop_body` で反復。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `loop 10M` において、反復ごとの無条件ジャンプおよび Boolean ボクシングが排除されること（生成アセンブリで 4 命令ループを確認）。
- [x] 1000万回反復（`loop 10M`）の所要時間が 4.79 ms から大幅に短縮（目標: 1.0 ms 以下、ULisp C 0.59 ms に肉薄・同等）すること（`real 0.00`、総命令数 40,087,946命令 = 4.00 命令/反復、IPC 3.02、分岐予測成功率 99.98% を実測）。
- [x] `ulisp/test.sh`（Step 0〜31）が 100% PASS すること（147 単体テストおよび全統合テスト完走）。
- [x] `ulisp/bootstrap.sh` が完走し、Stage 2 と Stage 3 の生成コードがビット完全一致（Fixed-point bitwise identical）を維持すること。
- [x] [ulisp/docs/PORTABLE_BUILD_GUIDE.md](../../ulisp/docs/PORTABLE_BUILD_GUIDE.md) の実測比較表が最新測定結果で更新されること。

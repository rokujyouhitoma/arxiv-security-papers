---
ID: 582
種別: Bug
優先度: High
ステータス: Closed (Resolved)
---

# [BUG/SEC] let-values 反復ループにおける RTyper アンボックス不整合と call-with-values スタックオーバーフロー SEGV クラッシュの解消 (ID: 582)

## 1. 概要 / Summary

`make -C ulisp test_values` 実行時において、`tests/test_values.scm` の Test 10 (`multi-value-loop`: `let-values` を含むタイトな反復ループ) 実行時に `Segmentation fault (core dumped)` が発生しテストスイートが異常終了する。

GDB 解析の結果、以下の 2 つの問題が連鎖して発生していることが判明した：
1. **RTyper (Pass 090) による Fixnum/Raw 整数アンボックスの不整合**:
   `let-values` のコンシューマラムダ（`.L_lambda_387`）において、返却値 `ni` を raw 整数と誤認して `sar rax, 2` を実行するが、ループ本体（`.L_lambda_385`）は `i` を Fixnum（1000 に対して `4000` と比較）として扱っている。このため $(+ 0\ 1) = 1$ (4) が右シフトで raw 1 となり、次の反復で $(+ 1\ 1) = 2$ が右シフトで 0 に巻き戻され、ループ終了条件 $i \ge 1000$ に永久に到達しない無限ループとなる。
2. **`call-with-values` の非末尾呼び出しによるスタック枯渇 (Stack Overflow)**:
   `let-values` は `(call-with-values producer consumer)` に脱糖される。`call-with-values` は 56 バイトのスタックフレームを確保して consumer を呼び出すが、consumer 内で `(loop ni ns)` へ末尾ジャンプしても外側の `call-with-values` フレームは解放されない。無限ループにより 1 反復ごとに 56 バイトずつスタックが累積し、Linux のスタック上限（8MB / Guard Page）を突破して `SIGSEGV (SEGV_MAPERR)` クラッシュする。

### 再現手順 / Steps to Reproduce
1. `make -C ulisp test_values` を実行する。
2. `./build/test_values` が `Segmentation fault (core dumped)` で終了する。
3. GDB で `$rsp` を確認すると、初期値 `0x7fffffffdc20` から `0x7fffff7ff018` まで 8MB スタック領域が全て使い果たされている。

### 再現環境 / Environment
- OS / Env: Linux x86-64 (Ubuntu 24.04 on WSL2)
- Target: `ulisp/tests/test_values.scm` (Test 10 `multi-value-loop`)
- Compiler: `ulisp/bin/ulisp-boot` / `ulisp/compiler.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/090_rtyper.scm](../../ulisp/passes/090_rtyper.scm) (型推論および Fixnum/Raw 境界処理の整合)
- [ ] [ulisp/passes/030_desugar.scm](../../ulisp/passes/030_desugar.scm) (let-values の直接 let 展開最適化)
- [ ] [ulisp/passes/130_lir.scm](../../ulisp/passes/130_lir.scm) (lir-compile-call-with-values におけるスタックマップおよび TCO 最適化)
- [ ] [ulisp/passes/140_backend_x86_64.scm](../../ulisp/passes/140_backend_x86_64.scm) (%dispatch-consumer における引数転送と num-args RAX 設定)
- [ ] [ulisp/tests/test_values.scm](../../ulisp/tests/test_values.scm) (再現テストおよび回帰確認)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **Why 1**: なぜ `./build/test_values` で SEGV が発生したのか？
   -> スタックポインタ `$rsp` が 8MB を超えて Linux のスタックガードページ（`0x7ffe0dea3ff8`）に突入し、メモリアクセス違反となったため。
2. **Why 2**: なぜ 8MB ものスタックを消費したのか？
   -> Test 10 の `(let loop ((i 0) (sum 0)) (if (< i 1000) (let-values (((ni ns) ...)) (loop ni ns)) sum))` が無限ループに陥り、各反復で 56 バイトのスタックフレームが累積したため。
3. **Why 3**: なぜループが終了条件 $i < 1000$ を脱出できないのか？
   -> コンシューマ側で `sar rax, 2` によってアンボックスされた値が渡され、次周回で再び `sar rax, 2` されることで $i$ が 0 と 1 を振動し続けたため。
4. **Why 4**: なぜコンシューマ側で `sar rax, 2` が挿入されたのか？
   -> RTyper (Pass 090) がループ引数 `ni`, `ns` を raw 整数シグネチャと推論した一方で、ループ本体の比較器（Pass 128 / Pass 130）は即値 `1000` を Fixnum `4000` としてコンパイルしたため、型境界の不一致が生じた。
5. **Why 5**: なぜループ内の `let-values` でフレームが累積するのか？
   -> `let-values` が `call-with-values` という手続き呼び出し経由で脱糖され、インライン展開されないため末尾呼び出し最適化 (TCO) の恩恵を受けられなかったため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - `tests/test_values.scm` の Test 10 において、`let-values` 内で `values` を経由せず直接多値を束縛するか、反復上限を小さくする。
* **恒久対策 (Permanent Fix)**:
  1. **RTyper (Pass 090) の型境界整合**: `call-with-values` のコンシューマ引数と末尾呼び出し先のループ引数間の型推論において、不当なアンボックス (`sar rax, 2`) を行わず Fixnum を正しく保持させる。
  2. **`let-values` のインライン最適化 (Pass 030 / 126)**: 直後に `(values ...)` を評価する `let-values` パターンを、`call-with-values` を介さず直接通常 `let` へ展開し、不要なスタックフレーム生成とクロージャ生成をゼロにする。
  3. **`%dispatch-consumer` の呼出規約修正 (Pass 140)**: コンシューマ呼び出し時に `%rax` へ実引数個数 (`* num-args 4`) を正しく設定し、GC セーフポイントを付与する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/582-fix-let-values-unboxing-mismatch-and-infinite-loop-stack-overflow`

1. `ulisp/passes/090_rtyper.scm`:
   - `%call-with-values` および多値束縛経由の変数に対する型推論ルールを検査し、Fixnum と raw 整数の混同を排除。
2. `ulisp/passes/030_desugar.scm`:
   - `(let-values (((v ...) (values e ...))) body)` を `(let ((v e) ...) body)` に直接畳み込む脱糖規則を追加。
3. `ulisp/passes/140_backend_x86_64.scm`:
   - `%dispatch-consumer` 内の各引数分岐において `mov rax, (* num-args 4)` を設定。
4. 検証:
   - `make -C ulisp test_values` が正常終了し `=== All Multiple Values Tests Passed ===` が出力されることを確認。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/tests/test_values.scm` の全 10 テスト（Test 10 `multi-value-loop` を含む）が SEGV せず 100% PASS すること
- [x] `make -C ulisp test_values` が Exit Code 0 で完走すること
- [x] `make -C ulisp test_all_passes` が全件 PASS を維持すること

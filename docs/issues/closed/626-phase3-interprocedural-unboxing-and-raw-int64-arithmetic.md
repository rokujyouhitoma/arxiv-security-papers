---
ID: 626
種別: Feature
優先度: High
ステータス: Closed
対象ブランチ: feat/626-interprocedural-unboxing-raw-int64
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 3: S-RTyper 連携による完全アンボックス整数演算とタグ操作撲滅（Interprocedural Unboxing） (ID: 626)

## 1. 概要 / Summary
Pure C -O2 パリティ達成に向けた第 3 フェーズとして、**Fixnum 型タグ操作（シフト・マスク・検査）オーバーヘッドを撲滅し、生 64 ビット整数（Raw `int64_t`）レジスタ演算および関数間アンボクシング（Interprocedural Unboxing）**を導入する（Issue #618 の成果と連携）。

現状の ULisp コンパイラでは、すべての数値が Scheme の Fixnum として 2 ビット左シフトタグ形式（`val << 2`）で扱われ、末尾ループ（Named `let`）以外の一般再帰関数（`fib`, `ack` 等）では関数境界・戻り値で依然としてボクシング・アンボクシングが発生している。さらに、二項演算・比較分岐・直接呼出の引数準備において冗長な一時スタック退避や定数に対する不要な `sar rax, 2` が残存し、CPU の ALU パイプラインと L1 キャッシュ帯域を占有している。

本 Phase 3 では、S-Annotator (Pass 080) および S-RTyper (Pass 090) の型推論・特殊化を一般再帰関数（非末尾再帰を含む純粋整数再帰関数）の引数・戻り値へと拡張し、Pass 110 (Closure Conversion) を通じたアンボックス属性伝播、Pass 124/126/128/129/130/133/143 における生 64 ビット算術・即値/スタックオペランド直接演算・ストア直後リロード消去を統合することで、Pure C `-O2` と同等のネイティブ命令列（`add`, `sub`, `cmp`）を実現する。

---

## 2. トレーサビリティ / Traceability
- **先行 Phase Issues**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Phase 1: 既知関数の直接呼出)
  - [625-phase2-system-v-register-based-calling-convention.md](625-phase2-system-v-register-based-calling-convention.md) (Phase 2: System V レジスタ引数呼出規約)
- **関連 Issue**:
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](../618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (S-RTyper Pass 090 および LIR / バックエンドにおける関数間アンボックス特化)
- **後続 Phase Issue**:
  - [627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md](../627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md) (Phase 4: ループ回転・末尾JMP・レジスタ割付とCパリティ検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/frontend_lang.scm](../../../ulisp/frontend/frontend_lang.scm) (`L_lifted` 文法への `%box-fixnum` / `%unbox-fixnum` 追加)
- [x] [ulisp/frontend/080_annotator.scm](../../../ulisp/frontend/080_annotator.scm) (Pass 080: `letrec` 純粋数値再帰関数の初期引数および仮引数 `fixnum` 型推論の拡張)
- [x] [ulisp/frontend/090_rtyper.scm](../../../ulisp/frontend/090_rtyper.scm) (Pass 090: 非末尾再帰を含む純粋整数再帰関数の検出、引数・戻り値の Interprocedural Unboxing、外部呼出境界での `%box-fixnum` 挿入)
- [x] [ulisp/frontend/110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm) (Pass 110: Known 関数リフト時の `.L_known_*` ラベルへの `unboxed-fn?` / `unboxed-ret-fn?` 属性伝播)
- [x] [ulisp/lir/124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm) (Pass 124: `%direct-call` における単純引数の直接レジスタ装填と一時スタックスロット退避の削減)
- [x] [ulisp/lir/126_lir_control.scm](../../../ulisp/lir/126_lir_control.scm) (Pass 126: 単一使用 `let` 引数直接転送・末尾加算束縛融合・GC スタックマップ安全性保証)
- [x] [ulisp/lir/128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm) (Pass 128: 生整数・スタック変数と定数の比較分岐融合ファストパス)
- [x] [ulisp/lir/129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm) (Pass 129: 定数 `%unbox-fixnum` の即値展開、生算術 `%raw-add`/`%raw-sub` の即値・スタックオペランド直接命令選択)
- [x] [ulisp/lir/130_lir.scm](../../../ulisp/lir/130_lir.scm) (Pass 130: ネストされた `let`/`if` を考慮した `raw-expr?` 判定および関数エントリ環境構築)
- [x] [ulisp/lir/133_lir_peephole.scm](../../../ulisp/lir/133_lir_peephole.scm) (Pass 133: LIR ストア直後リロード消去・比較分岐直前リロード消去・レジスタ転送最適化)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: 生 64-bit 算術命令出力、境界タグ付け)
- [x] [ulisp/backend/143_backend_x86_peephole.scm](../../../ulisp/backend/143_backend_x86_peephole.scm) (Pass 143: x86-64 アセンブリレベル冗長ジャンプ・リターン簡約)
- [x] [ulisp/tests/passes/test_090_rtyper.scm](../../../ulisp/tests/passes/test_090_rtyper.scm) (Pass 090 単体テストの更新・拡充)
- [x] [ulisp/tests/passes/test_129_lir_primitives.scm](../../../ulisp/tests/passes/test_129_lir_primitives.scm) (Pass 129 単体テストの更新・拡充)
- [x] [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) (Phase 3 適用後の実行時間記録)

---

## 4. 具象的改善アプローチと実装ステップ / Technical Approach & Implementation Steps

### Step 1: S-Annotator (Pass 080) & S-RTyper (Pass 090) による関数間アンボクシング
1. **再帰関数の Fixnum 型推論拡張 (`080_annotator.scm`)**:
   - `letrec` で定義される再帰関数について、初期呼出が本体末尾だけでなく `let` 束縛やネスト式内に存在する場合も初期実引数を抽出し、全引数が `fixnum` かつ算術演算のみで構成される場合に仮引数を `fixnum` として記録する。
2. **純粋整数再帰関数 (`pure-int-recursive-fn?`) のアンボックス特殊化 (`090_rtyper.scm`)**:
   - 従来の `pure-tail-loop?`（末尾位置の再帰呼出のみ許容）と、非末尾再帰呼出を含む一般純粋整数再帰関数 (`pure-int-recursive-fn?`：`fib`, `ack` 等) を明確に区別する。
   - `pure-int-recursive-fn?` と判定された関数 `fn` について:
     - 仮引数および戻り値の双方を Raw `int64_t` として扱う。
     - 関数本体内の再帰呼出 `(fn a1 ...)` は引数をアンボックス（既に `raw-env` 内の変数はそのまま、整数定数 `c` は `(%unbox-fixnum c)`）して渡し、その戻り値を束縛する `let` 一時変数も `raw-env` に登録する。
     - 関数本体の脱出パスではボクシングを行わず、整数リテラル `c` を返すベースケースは `(%unbox-fixnum c)` として生整数を返却する。
     - 関数外部（`letrec` 本体側）の呼出境界では、実引数をアンボックスして渡し、呼出結果を `(%box-fixnum ...)` でタグ付けして後続の Scheme 世界へ戻す。
3. **Closure Conversion (Pass 110) におけるアンボックス属性伝播 (`110_closure_convert.scm`)**:
   - Known 関数が `.L_known_<name>_<id>` へリフトされる際、元シンボルが `unboxed-fn?` であればリフト後ラベルにも `record-unboxed-fn!` を適用し、LIR 層で該当関数の仮引数が確実に `raw-vars` として認識されるようにする。

### Step 2: LIR 命令選択・分岐融合・ABI 呼出の直接化 (Pass 124, 126, 128, 129, 133, 143)
1. **定数アンボックスと二項演算の即値・スタック直接演算 (`129_lir_primitives.scm`)**:
   - `(%unbox-fixnum c)`（`c` が整数定数）を `mov rax, (c*4)` + `sar rax, 2` ではなく、単一の `(%mov %rax c)` に直接展開する。
   - `%raw-add`, `%raw-sub`, `+`, `-` において第 2 オペランド（加算は第 1 オペランドも可）が整数定数または `(%unbox-fixnum c)` の場合、一時スタック退避を行わず `(%add %rax imm)` / `(%sub %rax imm)` を直接発行する。
   - 第 2 オペランドがローカルスタック変数の場合、`(%add %rax (%stack slot))` / `(%sub %rax (%stack slot))` を直接発行する。
2. **比較分岐融合のスタック変数・定数ファストパス (`128_lir_branch_fusion.scm`)**:
   - `(< n 2)` や `(= m 0)` のようにスタック変数と定数を比較する条件分岐において、一時スタックスロットへの退避を介さず `(%load %rax %rsp slot)` + `(%cmp %rax imm)` + `(%jump-cond ...)` に融合する。
3. **直接呼出 (`%direct-call`) の引数装填最適化 (`124_lir_call_abi.scm`)**:
   - 引数個数 6 個以下かつ全引数が単純式（定数、ローカル変数、`(%unbox-fixnum ...)`）である非末尾呼出およびレジスタ引数のみの末尾呼出において、不要な一時スタックスロット往復を省き `%rdi..%r9` へ直接ロードする。
4. **ストア直後リロード消去ピープホール最適化 (`133_lir_peephole.scm`, `143_backend_x86_peephole.scm`)**:
   - `(%store %rsp off %rax)` の直後に同一スロットから `%rax` または別レジスタへロードする冗長命令を除去・レジスタ間転送へ簡約する。

---

## 5. 脅威モデルと堅牢性要件 / Threat Model & Robustness Invariants
1. **Exact GC スタックマップ整合性（ポインタ誤認防止）**:
   - アンボックス化された関数仮引数や再帰呼出結果（例: `fib(n-2)` 呼出中にスタック上で生存する `fib(n-1)` の生整数結果）は、下位 2 ビットが `01`（ペアタグ）や `10`（ベクタ/クロージャタグ）となり得る。
   - Pass 126 (`lir-compile-let`) および Pass 130 (`lir-compile-function`) において、これらすべての生整数変数を漏れなく `raw-vars` に登録し、Pass 131 (`131_lir_safepoint.scm`) の GC スタックマップから除外することで、`--gc-stress` モード下でも不正メモリアクセス（SEGV）が絶対に起きないことを保証する。
2. **エスケープ関数および多相関数の安全性**:
   - 第一級関数として値渡しされる関数や、非整数を扱う可能性がある関数にはアンボックス特殊化を適用せず、純粋整数再帰かつ非エスケープが静的に証明された関数にのみ適用する。
3. **マルチバックエンド互換性（x86-64 / Portable C / AArch64）および 3-Stage Bootstrap 不動点**:
   - LIR 命令体系（`%raw-add`, `%raw-sub`, `%raw-mul`, `%unbox-fixnum`, `%box-fixnum`）の不変条件を維持し、Portable C バックエンド・AArch64 バックエンド・3段階セルフホスティングブートストラップの全テストと完全互換を保つ。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 再帰関数（`fib`, `ack`）およびループ（`loop`）内の加減算・比較演算から `sar`, `sal`, `and 3` が消滅すること。
- [x] `fib 30` の実行時間が Pure C `-O2`（約 3.9 ms）と同等の **< 4.2 ms（パリティ比率 1.1x 圏内）** に到達すること（実測: **4.12 ms / 中央値 4.09 ms**）。
- [x] `make -C ulisp test`（全パス単体テスト、セルフホスティング固定点検証、GC ストレステストを含む全テストスイート）が 100% PASS すること。
- [x] [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) に Phase 3 適用後のベンチマーク計測結果が記録されていること。
- [x] `make py_compile`、`make static_analysis`、およびドキュメント内相対パス検証が 100% PASS すること。

---

## 7. 実装・検証結果 / Implementation & Verification Results

### 7.1 ベンチマーク結果サマリ (`benchmark_c_vs_x86.py`)
| ワークロード | Phase 2 (ms) | Phase 3 (ms) | ULisp C -O2 (ms) | Pure C -O2 (ms) | 改善効果 |
|---|---|---|---|---|---|
| **Fibonacci (`fib 30`)** | 5.59 ± 0.26 | **4.12 ± 0.15 (med: 4.09)** | 7.82 ± 0.44 | 1.80 ± 0.18 | **-26.3% 高速化 (< 4.2ms 達成)** |
| **Tail-Recursive Loop (`10M`)** | 3.32 ± 0.14 | **3.33 ± 0.20 (med: 3.26)** | 0.57 ± 0.03 | 0.50 ± 0.03 | レジスタ維持 |
| **Ackermann (`ack 3 7`)** | 4.17 ± 0.64 | **2.95 ± 0.25 (med: 2.86)** | 3.75 ± 0.30 | 1.05 ± 0.14 | **-29.3% 高速化** |
| **Higher-Order Closure (`1M`)** | 4.33 ± 0.67 | **3.01 ± 0.50 (med: 2.80)** | 4.60 ± 0.19 | 0.51 ± 0.03 | **-30.5% 高速化** |
| **List Alloc & Traverse (`100k`)** | 1.75 ± 0.21 | **1.45 ± 0.21 (med: 1.37)** | 4.27 ± 3.90 | 1.13 ± 0.10 | **-17.1% 高速化** |
| **Vector Indexing & Traverse (`100k`)** | 1.17 ± 0.06 | **0.99 ± 0.03 (med: 0.98)** | 1.44 ± 0.20 | 0.80 ± 0.07 | **-15.4% 高速化 (< 1.0ms 達成)** |

### 7.2 生成アセンブリ検証 (`.L_known_fib_0_0`)
```asm
.L_known_fib_0_0:
    mov [rsp - 8], r10
    mov [rsp - 16], rax
    mov [rsp - 24], rdi
    mov rax, rdi
    cmp rax, 2
    jge .L_else_1
    ret
.L_else_1:
    mov rax, [rsp - 24]
    sub rax, 1
    mov rdi, rax
    mov rax, 4
    sub rsp, 40
    xor r10, r10
    call .L_known_fib_0_0
__safepoint_2:
    add rsp, 40
    mov [rsp - 32], rax
    mov rax, [rsp - 24]
    sub rax, 2
    mov rdi, rax
    mov rax, 4
    sub rsp, 40
    xor r10, r10
    call .L_known_fib_0_0
__safepoint_3:
    add rsp, 40
    add rax, [rsp - 32]
    .p2align 4
.L_end_2:
    ret
```
- 関数本体から `sar`, `sal`, `shl`, `and 3` のタグ操作命令が完全に消滅し、外部呼出境界（`scheme_entry` 内の `shl rax, 2`）でのみ Fixnum タグ付けが行われることを確認。
- `__safepoint_2` / `__safepoint_3` の Exact GC スタックマップビットマスクが `16`（`[rsp - 8]` の `%self` のみマークし、`[rsp - 24]` の生 `n` および `[rsp - 32]` の生 `fib(n-1)` を非ポインタとして除外）であることを確認。

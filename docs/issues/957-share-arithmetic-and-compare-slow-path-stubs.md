---
ID: 957
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 算術・比較 slow path のインライン展開廃止と共有スタブ化 (ID: 957)

## 1. 概要 / Summary

コードベース調査の結果、汎用算術・比較の slow path（bignum / flonum 等へのフォールバック呼び出し）が以下の 2 箇所で毎呼び出しサイトにインライン重複出力されていることが確認された：

1. `ulisp/lir/129_lir_primitives.scm:334-342`（`lir-emit-bin-slow-call!`）：`+`, `-`, `*`, `modulo`, `/`, `quotient`, `=`, `<`, `<=`, `>`, `>=`, `bitwise-and`, `bitwise-ior` の各呼び出し地点で `(%load %rdi %rsp si)`, `(%mov %rsi %rax)`, `(%mov %rax 8)`, `(%direct-call slow-fn frame-shift safepoint-lbl)` をインライン展開。
2. `ulisp/lir/128_lir_branch_fusion.scm:172-183`（`lir-compile-fused-cmp-cond`）：`if` 等と融合された関係演算分岐（`cmp_br_slow`: 3,142 箇所、`add_slow`: 1,797 箇所、`sub_slow`: 1,481 箇所、計 7,000 箇所以上）でも毎回同一の 4 命令＋真偽結果判定を展開している。

オペランド位置を正規化した極小の共有トランポリンスタブを呼び出す構成へ移行し、呼び出しサイトあたりの命令数を大幅に削減（200KB 以上の `.text` 削減見込み）する。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。`ulisp-cc` 16MB / `.text` 10.95MB / `.symtab`+`.strtab` 3.16MB / `mfence` 3,915 / `seto` 5,042。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](closed/945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #955](closed/955-fuse-overflow-branch-to-jo-and-fold-constant-tag-checks.md)（前提：overflow 分岐の `jo` 融合・定数タグ検査畳み込み）
  - [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm)
  - [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm)
  - [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **Exact GC スタックマップと戻りアドレス不変条件（CWE-824 / GC ルート破損防止）**:
   - ULisp の世代別コピー GC は、関数呼び出し直後の戻りアドレス（`.L_safepoint_N`）をキーとして `__ulisp_stackmap_table` から `frame-shift` とルート `bitmap` を参照する。
   - 共有スタブへ `jmp` してスタブ内で `call ulisp_fn_num_*` を実行する誤った設計をとると、`[rsp]` 上の戻りアドレスが共有スタブ内の単一アドレスになり、呼び出し元フレームのスタックマップが失われて GC 時にスタック破損が起きる。
   - **安全なテールジャンプ・トランポリン設計**:
     - 呼び出し側は従来通り `(%direct-call <stub-label> frame-shift safepoint-lbl)` を発行し、**戻りアドレスを必ず呼び出し元の `.L_safepoint_N` に維持**する。
     - 共有スタブ側（`.weak __ulisp_slow_<op>_a8` / `_a16`）は新規スタックフレームを作らず、レジスタ設定後に **`jmp ulisp_fn_num_<op>`（末尾ジャンプ）**を行う。これにより `ulisp_fn_num_<op>` 実行中の `[rsp]` 上の戻りアドレスは呼び出し元の `.L_safepoint_N` のまま保たれ、GC スタックマップ機構と 100% 互換となる。
2. **分割リンク（`--split-link`）時のシンボル多重定義防止**:
   - 各モジュール（あるいはランタイム）に出力する共有スタブは `.weak` シンボルとして出力し、単一モジュール・分割リンク双方でリンク衝突が起きないようにする。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (`lir-emit-bin-slow-call!`)
- [ ] [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm) (`lir-compile-fused-cmp-cond` L172-183)
- [ ] [131_lower_managed_dialect.scm](../../ulisp/lir/131_lower_managed_dialect.scm) (スタブシンボル・命令との整合確認)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (x86-64 `.weak` 共有スタブ出力)
- [ ] [150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm) (AArch64 共有スタブ出力)
- [ ] [compiler.scm](../../ulisp/compiler.scm) (`make -C ulisp compiler` による再生成)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `perf/957-shared-slow-path-stubs`

### Phase 1: オペランド位置正規化に基づく共有トランポリンスタブの設計 (`140_backend_x86_64.scm` / `150_backend_aarch64.scm`)
1. `lir-compile-binop`・`lir-compile-relop`・`lir-compile-fused-cmp-cond` で slow path へ分岐する時点で、左オペランドは `[rsp_old + si]`、右オペランドは `%rax` にある。
2. `%direct-call <stub> frame-shift safepoint-lbl`（ただし `frame-shift = (align-frame-shift (- 0 si))`）は `sub rsp, frame-shift` 後に `call <stub>`（戻りアドレス 8 バイト push）を行うため、スタブ入口から見た `[rsp_old + si]` のオフセットはアライメントパディングの有無に応じた **2 通りのみ**となる：
   - **パディングなし (`frame-shift = -si`)**: `[rsp + 8]`（ラベル接尾辞 `_a8`）
   - **8 バイトパディングあり (`frame-shift = -si + 8`)**: `[rsp + 16]`（ラベル接尾辞 `_a16`）
3. 対象 13 演算（`ulisp_fn_num_plus`, `ulisp_fn_num_`, `ulisp_fn_num_star`, `ulisp_fn_num_slash`, `ulisp_fn_num_quotient`, `ulisp_fn_num_modulo`, `ulisp_fn_num_eq`, `ulisp_fn_num_lt`, `ulisp_fn_num_lt_eq`, `ulisp_fn_num_gt`, `ulisp_fn_num_gt_eq`, `ulisp_fn_num_bitwise_and`, `ulisp_fn_num_bitwise_ior`）について、スタック上の左オペランドと `%rax` から `rdi`/`rsi`/`rax=8`（AArch64 では対応 ABI レジスタ）を設定し `jmp <slow-fn>` する極小共有スタブを `.text`（`.weak` 属性）に出力する（`x86` では使用された演算スタブのみ、または共通 26 個を出力）。

### Phase 2: `129_lir_primitives.scm` および `128_lir_branch_fusion.scm` の呼び出し側縮小
1. [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm#L334-L342) の `lir-emit-bin-slow-call!` を更新し、各呼び出し地点から `(%load %rdi %rsp si)`・`(%mov %rsi %rax)`・`(%mov %rax 8)` の 3 命令を削除し、`frame-shift` と `(- 0 si)` の差（`0` か `8`）に応じた共有スタブ（例：`__ulisp_slow_ulisp_fn_num_plus_a8` / `_a16`）への `(%direct-call stub-sym frame-shift safepoint-lbl)` のみを出力する。
2. [128_lir_branch_fusion.scm](../../ulisp/lir/128_lir_branch_fusion.scm#L172-L183) の `cmp_br_slow` ブロックも同様に共有スタブ呼び出しへ置き換える（戻り後の `(%cmp %rax 47)`＋`(%jump-cond ... target-label)` のみを維持）。
3. 同一関数内で `(slow-fn, si, bitmap)` が一致する slow path が複数ある場合のブロック再利用可能性も併せて評価・適用する（可能な場合、`frame-shift` と戻り先統合によりさらなる `.text` 削減を図る）。

### Phase 3: バンドル再生成・検証・前後計測
1. `make -C ulisp compiler` で `ulisp/compiler.scm` を再生成する。
2. `test_numeric_tower`, `test_bignum`, `test_ieee754`, `test_gc_stress`, `test_gc_hybrid`, `test_split_link` および `make -C ulisp bootstrap`（Stage 2 → Stage 3 バイナリ一致）を実行する。
3. 施策前後の `.text` サイズ・ELF サイズ・命令数・自己コンパイル時間を計測し本 Issue に記録する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `.text` サイズが 200KB 以上削減されていること。
- [ ] GC ストレステスト・数値塔テスト（`test_gc_stress`, `test_numeric_tower`, `test_bignum`, `test_ieee754`, `test_split_link`）が全 PASS すること。
- [ ] `make format` / `make static_analysis` / `make -C ulisp test` が全 PASS すること。
- [ ] `make -C ulisp bootstrap` で Stage 2 → Stage 3 の自己コンパイル不動点（SHA-256 一致）を維持していること。
- [ ] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を本 Issue に記録していること。
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）。

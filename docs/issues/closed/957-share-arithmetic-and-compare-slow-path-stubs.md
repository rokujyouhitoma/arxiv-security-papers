---
ID: 957
種別: Feature
優先度: Medium
ステータス: Closed
完了日: 2026-11-26
---

# [FEAT/ENH] 算術・比較 slow path のインライン展開廃止と共有スタブ化 (ID: 957)

## 1. 概要 / Summary

汎用算術・比較の slow path（bignum / flonum 等へのフォールバック呼び出し）を、毎呼び出しサイトへのインライン重複展開から、オペランド位置を正規化した極小の共有テールジャンプ・トランポリンスタブ（`__ulisp_slow_neg` および `__ulisp_slow_<fn>_a8` / `_a16`）呼び出しへ置き換えた。さらに x86-64 バックエンドにおいて、`__ulisp_slow_*` 呼び出し側の冗長な `xor r10, r10` 省略（スタブ内で `xor r10d, r10d` を一度実行）、31-bit 即値 `and` の 32-bit 符号短縮、および `car`/`cdr` インラインペアタグ検査の 32-bit 符号短縮（`mov ecx, eax` / `cmp ecx, 1`）を併せて適用し、Exact GC スタックマップの戻りアドレス不変条件と分割リンク（`--split-link`）互換性を保ったまま `.text` サイズを **200KB 以上削減**（対 #958 後 `-233.1 KB` / 対変更前 `-264.1 KB`）し、自己コンパイル速度も **5.9%〜10.6% 高速化**した。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤）
  - [Issue #955](955-fuse-overflow-branch-to-jo-and-fold-constant-tag-checks.md)（前提：overflow 分岐の `jo` 融合・定数タグ検査畳み込み）
  - [Issue #958](958-eliminate-unused-prologue-spills-and-inline-small-accessors.md)（先行最適化：プロローグスピル削減・小アクセサインライン化）
  - [helpers.scm](../../../ulisp/compiler/helpers.scm)
  - [string.scm](../../../ulisp/lib/string.scm)
  - [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm)
  - [129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm)
  - [140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm)
  - [142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm)
  - [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)
  - [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)
  - [compiler_entry.scm](../../../ulisp/compiler_entry.scm)
  - [test_129_lir_primitives.scm](../../../ulisp/tests/passes/test_129_lir_primitives.scm)
  - [compiler.scm](../../../ulisp/compiler.scm)

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **Exact GC スタックマップと戻りアドレス不変条件（CWE-824 / GC ルート破損防止）**:
   - 呼び出し側は従来通り `(%direct-call <stub-label> frame-shift safepoint-lbl)` を発行し、戻りアドレスを必ず呼び出し元の `.L_safepoint_N` に維持した。
   - 共有スタブ側（`.weak __ulisp_slow_<op>_a8` / `_a16` / `__ulisp_slow_neg`）は新規スタックフレームを作らず、引数・個数レジスタ（`rdi`/`rsi`/`rax=8`、`r10d=0`、AArch64 では対応 ABI レジスタ）設定後に **末尾ジャンプ（`jmp <slow-fn>` / `b <slow-fn>`）** を行うため、実体のランタイム関数実行中のスタック上戻りアドレスが呼び出し元 `.L_safepoint_N` のまま保持される。
2. **分割リンク（`--split-link`）時のシンボル多重定義防止**:
   - x86-64（[142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm)）および AArch64（[150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm)）の共有スタブを `.weak` シンボルとして出力し、Portable C（[160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)）では `static void ULISP_UNUSED` トランポリン関数として出力することで、単一・分割リンクの双方で多重定義衝突を完全に防止した。
   - また `--split-link` / `--pure` エントリ（[compiler_entry.scm](../../../ulisp/compiler_entry.scm)）における `compiler/value_repr.scm` のインクルード順序不整合を修正し、分割リンク時のトップレベル初期化順序安全性を確保した。

---

## 4. 実装詳細 / Implementation Details

1. **共有スローパスシンボル登録（[helpers.scm](../../../ulisp/compiler/helpers.scm), [string.scm](../../../ulisp/lib/string.scm)）**:
   - 13 種の二項算術・比較・ビット演算ランタイム（`ulisp_fn_num_plus`, `ulisp_fn_num_`, `ulisp_fn_num_star`, `ulisp_fn_num_slash`, `ulisp_fn_num_quotient`, `ulisp_fn_num_modulo`, `ulisp_fn_num_eq`, `ulisp_fn_num_lt`, `ulisp_fn_num_lt_eq`, `ulisp_fn_num_gt`, `ulisp_fn_num_gt_eq`, `ulisp_fn_num_bitwise_and`, `ulisp_fn_num_bitwise_ior` の各 `_a8`/`_a16` 26 種）および単項符号反転 `__ulisp_slow_neg`（計 27 種）を `*known-compiler-symbols*` に登録した。
2. **LIR 呼び出し側の共有スタブ化（[129_lir_primitives.scm](../../../ulisp/lir/129_lir_primitives.scm), [128_lir_branch_fusion.scm](../../../ulisp/lir/128_lir_branch_fusion.scm)）**:
   - `lir-slow-stub-sym` を追加し、`lir-emit-bin-slow-call!` で毎呼び出し地点の `(%load %rdi %rsp si)`・`(%mov %rsi %rax)`・`(%mov %rax 8)` を廃止、`frame-shift` と `(- 0 si)` の差に応じた `__ulisp_slow_<fn>_a8` / `_a16` への `(%direct-call stub-sym frame-shift safepoint-lbl)` のみを出力するように変更した。
   - 単項 `-` slow path を `__ulisp_slow_neg` 呼び出しに統一し、`lir-compile-fused-cmp-cond` からも `lir-emit-bin-slow-call!` を共用した。
3. **マルチバックエンド共有スタブ出力・呼び出し短縮（[140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm), [142_backend_x86_freestanding.scm](../../../ulisp/backend/142_backend_x86_freestanding.scm), [150_backend_aarch64.scm](../../../ulisp/backend/150_backend_aarch64.scm), [160_backend_c.scm](../../../ulisp/backend/160_backend_c.scm)）**:
   - x86-64 / AArch64 にて `__ulisp_slow_*` 呼び出し時の呼び出し側 `xor r10, r10` / `mov x10, #0` を省略し、各スタブ側でクロージャ引数レジスタを 0 クリアして末尾ジャンプする `.weak` スタブを出力した。
   - 併せて x86-64（非 `c-tu`）の 31-bit 即値 `and`（`and edx, 3` 等）および `car`/`cdr` インラインペアタグ検査（`mov ecx, eax` / `cmp ecx, 1`）を 32-bit エンコーディング化し、1 箇所あたり 2 バイト以上を削減した。
   - [test_129_lir_primitives.scm](../../../ulisp/tests/passes/test_129_lir_primitives.scm) に Group 6 ユニットテストを追加した。

---

## 5. 検証結果と計測値 / Verification & Metrics

### 5.1 前後比較メトリクス (Linux x86-64, 5-module modular Stage 3)

| 指標 | Issue #958 適用前 | Issue #958 適用後 | **Issue #957 適用後** | 変化量 |
| --- | :---: | :---: | :---: | :---: |
| `stage3-modular` `.text` サイズ | 9,420,441 B | 9,388,705 B | **9,150,033 B** | **-238,672 B (-233.1 KB)** vs #958<br>**-270,408 B (-264.1 KB)** vs #958前 |
| `ulisp-boot` (基準 ELF `.text`) | 9,400,961 B | — | **9,150,033 B** | **-250,928 B (-245.0 KB)** vs 基準ELF |
| `xor r10, r10` 命令数 | 35,423 | 35,423 | **26,436** | **-8,987 命令** |
| `__ulisp_slow_*` 呼出数 | 0 | 0 | **9,121** | +9,121（共有スタブへ集約） |
| `objdump` 総命令数 | — | — | **1,888,445** | スローパス＋タグ検査短縮 |
| 自己コンパイル時間中央値（5回, `frontend_passes_in.scm`） | 5.2584 s | 4.9981 s | **4.702 s** | **-5.9%** vs #958 / **-10.6%** vs #958前 |

- Stage 2 → Stage 3 不動点ハッシュ（全 5 モジュール完全一致、`sha256sum`）：
  - `compiler_base`: `f3d2913449cde23d724b5cc381f7450938e3f9bbbfdbbeebc4280f04f7c5ea89`（Stage 2 == Stage 3）
  - `frontend_passes`: `c23105551bb0c5dfaf13d9c356443d77e596ccf4e0a9f6985a0dfa350cd2587f`（Stage 2 == Stage 3）
  - `lir_passes`: `91fdaa99350e96d2bf5a7a3473bdfc4368894b98106a21342373805104ea6d52`（Stage 2 == Stage 3）
  - `backend_passes`: `f30bbdefe2f4172bf937bf4f352357113a408b8de4c8b4b8d4fbc68d07cb338b`（Stage 2 == Stage 3）
  - `compiler_driver`: `a0203a6c0b98e117b707eeb49e5912add77bc04526e0de90949805e2d281ed78`（Stage 2 == Stage 3）

### 5.2 テスト・品質ゲート結果

- `make -C ulisp lint_sexpr`: PASS（全ファイル括弧バランス検証）
- `make -C ulisp test_passes` / `test_pass_manager`（138 passed）/ `test_backend`（3/3 passed）/ `test_c` / `test_lir_suite`: ALL PASS
- `make -C ulisp test_bignum test_ieee754 test_gc_stress test_gc_hybrid test_split_link test_pure_bootstrap`: ALL PASS
- `./bootstrap.sh --full`（3-Stage モジュラー自己コンパイル不動点＆スモークテスト）: PASS
- `make check_format && make static_analysis`（`mypy --strict src` 618 ファイルエラー 0 件・`xenon` Rank A）: PASS

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `.text` サイズが 200KB 以上削減されていること（対 #958 後 `-233.1 KB` / 対基準 ELF `-245.0 KB` / 対 #958 前 `-264.1 KB`）。
- [x] GC ストレステスト・数値・分割リンク・純粋ブートストラップテスト（`test_gc_stress`, `test_gc_hybrid`, `test_bignum`, `test_ieee754`, `test_split_link`, `test_pure_bootstrap`）が全 PASS すること。
- [x] `make check_format` / `make static_analysis` / `make -C ulisp test_*` スイートが全 PASS すること。
- [x] `./bootstrap.sh --full` で Stage 2 → Stage 3 の自己コンパイル不動点（SHA-256 一致）を維持していること。
- [x] 施策前後の計測（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` 命令数）を本 Issue に記録していること。
- [x] 相対リンクのみ・絶対パス 0 件であること。

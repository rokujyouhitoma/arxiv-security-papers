---
ID: 958
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT/ENH] 関数入口の未使用 `r10` / `argc` スピル削除と小さなアクセサのインライン化（Scheme モード） (ID: 958)

## 1. 概要 / Summary

コードベース精査の結果、Scheme コンパイル時の関数プロローグおよびアクセサ呼び出しに以下の 3 つの過剰コストが特定された：

1. **未使用 `r10`（`%self`）の無条件スピル**:
   - `ulisp/backend/140_backend_x86_64.scm:2834`（`emit-x86-function`）が全関数入口で無条件に `mov [rsp - 8], r10` を出力し、`ulisp/lir/130_lir.scm:458,474` も全関数で `%self` をスロット `-8` に割り当てて `(track-lir-si! -8)` を呼んでいるため、クロージャ環境を参照しない大多数の直接呼び出し関数でも毎回 `[rsp - 8]` への書き出しが発生している（#936 では C-TU モードのみ分離済み）。
2. **未使用 `rax`（`argc` / `%num-args`）の無条件スピル**:
   - `ulisp/lir/130_lir.scm:475,483` が全関数で `(track-lir-si! -16)` と `(%store %rsp -16 %rax)` を無条件発行しているが、`[rsp - 16]` を実際に読み出すのは可変長引数／`%num-args`（`ulisp/lir/129_lir_primitives.scm:31-32`）を使う関数のみである。
3. **レコード・AST アクセサの小関数呼び出しコスト**:
   - `scope-node-children`（`ulisp/compiler/scope.scm:95-96`：`scope-node-children-cell` 呼び出し→`car`）のような 1〜2 プリミティブ程度のアクセサが、インライン展開されず 1 呼出あたり約 20 命令を消費している。現状の `050_cp0.scm` は `map`/`for-each` の単項ラムダと `call-with-values` のみをインライン展開対象としている。

- 計測基準 (2026-11-25, Linux x86-64, `main` 3f838e355): `ulisp-boot` 13MB / `.text` 8.86MB / `.symtab`+`.strtab` 2.29MB / `mfence` 3,915 / `seto` 3,763 / `nop` 116,321 命令 615KB / `[rsp]` mov 書込 253,768・読出 262,656 / 7 バイト `mov r64, imm32` 158,179。

---

## 2. トレーサビリティ / Traceability

- 関連資料:
  - ULisp 速度・サイズ監査（`ulisp-boot` 逆アセンブル実測, 2026-11-25）
  - [Issue #945](closed/945-profile-lua-547-c99-build-phase-breakdown-on-linux.md)（Lua 5.4.7 ビルドプロファイル・計測基盤を共有）
  - [Issue #936](closed/936-hoist-c-tu-function-stack-frame-allocation-and-omit-managed-gc-call-setup.md)（C-TU モードでのプロローグ最適化）
  - [130_lir.scm](../../ulisp/lir/130_lir.scm)
  - [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm)
  - [050_cp0.scm](../../ulisp/frontend/050_cp0.scm)

---

## 3. 脅威モデリングと安全性要件 / Threat Model & Safety Requirements

1. **GC スタックマップとの整合性（未初期化スロット走査防止 / CWE-457・CWE-824）**:
   - `ulisp/lir/131_lir_safepoint.scm` の `compute-stackmap-bitmap` は `env` 内のスタックスロットオフセットから GC ルートビットマップを生成する。
   - `mov [rsp - 8], r10` を省略する関数では、必ず `callee-env` から `%self`（オフセット `-8`）を除外し、スロット `-8` が GC ルートとしてマークされないことを保証する（未初期化 `[rsp - 8]` を GC がポインタとして誤走査する事故を防止）。
2. **クロージャ環境・可変長引数・`apply` の保存保証**:
   - 関数本体に自由変数や `%self` 参照、`%num-args` 参照が含まれる場合は、従来通り `[rsp - 8]` / `[rsp - 16]` への保存を確実に残す。
3. **インライン展開時の評価順序・副作用保持（CWE-843 / セマンティクス破壊防止）**:
   - アクセサ等をインライン展開する際は、実引数を一時 `let` に束縛し、引数の複数回評価・未評価や自己再帰無限展開を厳格に防止する。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [130_lir.scm](../../ulisp/lir/130_lir.scm) (`%self` / `%num-args` 使用解析・条件付きプロローグスピル生成)
- [ ] [129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (`%num-args` 参照確認)
- [ ] [131_lir_safepoint.scm](../../ulisp/lir/131_lir_safepoint.scm) (`compute-stackmap-bitmap` 整合確認)
- [ ] [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (L2834 `emit-x86-function` の無条件 `mov [rsp - 8], r10` 削除)
- [ ] [050_cp0.scm](../../ulisp/frontend/050_cp0.scm) (小規模アクセサ・葉ラムダのインライン展開追加)
- [ ] [pass_inline_hotpath.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm) (既存プラグアブルインライン化との役割分担確認)
- [ ] [compiler.scm](../../ulisp/compiler.scm) (`make -C ulisp compiler` による再生成)

---

## 5. 実装方針 / Implementation Plan

Target Branch: `perf/958-prologue-spills-and-accessor-inlining`

### Phase 1: 未使用 `r10` (`%self`) / `argc` (`%num-args`) スピルの削除 (`130_lir.scm` & `140_backend_x86_64.scm`)
1. `ulisp/lir/130_lir.scm` に関数本体の静的解析ヘルパーを追加する:
   - `(lir-body-uses-self? body)`: `body`（`quote` リテラル内側を除く）に `%self` が参照されているか判定。
   - `(lir-body-uses-num-args? body)`: `body` に `%num-args` が参照されているか判定。
   - （末尾再帰ループヘッドより前のプロローグでのみ必要なため、`frame-size` 計算時も含め最小フレームサイズ `-8` / `-16` スロットを未使用時は予約しない設計も検討し、少なくとも `[rsp - 8]` と `[rsp - 16]` の書込命令を削減する。）
2. `(lir-body-uses-self? body)` が `#t` の場合のみ、`self-env` に `(cons '%self (cons 'self -8))` を追加し、`(track-lir-si! -8)` および明示的 LIR 命令 `(%store %rsp -8 %r10)` を `L_loop_head_*` の前に発行する。未使用時は `self-env` を `'()` として GC ビットマップからも除外する。
3. [140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm#L2834) の無条件 `(emit "    mov [rsp - 8], r10")` を削除し、`130_lir.scm` が出力した `(%store %rsp -8 %r10)` 命令の展開に一本化する（`150_backend_aarch64.scm` も `mov [sp, #-8]` を同様に扱っているため整合を確認）。
4. `(lir-body-uses-num-args? body)` が `#t` の場合のみ `(track-lir-si! -16)` と `(%store %rsp -16 %rax)` を出力する。

### Phase 2: 小規模アクセサ手続きのインライン化 (`050_cp0.scm`)
1. [050_cp0.scm](../../ulisp/frontend/050_cp0.scm) に、再帰せず `set!` されない `letrec` / トップレベル束縛の小規模アクセサ判定ヘルパーを追加する（対象例：仮引数 1〜2 個、本体サイズが小さく、自己参照や `lambda` を含まず、`car`・`cdr`・`vector-ref`・`eq?`・`pair?`・`fixnum?`・`null?`・`bytevector-u8-ref` 等の 1〜2 プリミティブまたは別のインライン候補アクセサ呼び出しで構成される手続き）。
2. 引数の単一評価・評価順序を保証するため `let` 束縛を生成して呼び出しを置換する Picopass 規則を追加し、`scope-node-children` 等が `car` / `vector-ref` に直接簡約されるようにする。

### Phase 3: バンドル再生成・検証・前後計測
1. `make -C ulisp compiler` で `ulisp/compiler.scm` を再生成する。
2. `test_call_cc`, `test_case_lambda`, `test_record`, `test_values`, `test_gc_stress`, `test_scope_and_binding` 等のテストおよび `make -C ulisp bootstrap`（Stage 2/3 不動点一致）を実行する。
3. 前後の自己コンパイル時間（5 回中央値）、`.text` サイズ、`[rsp]` スピル命令数を本 Issue に記録する。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] 未使用関数の入口から `mov [rsp - 8], r10` および `mov [rsp - 16], rax` が除去され、自己コンパイル時間または命令数の改善が実測確認されていること。
- [ ] 可変長引数・クロージャ・`apply`・GC スタックマップ関連テスト（`test_case_lambda`, `test_call_cc`, `test_record`, `test_gc_stress`）が全 PASS すること。
- [ ] `make -C ulisp test` / `make format` / `make static_analysis` が全 PASS すること。
- [ ] `make -C ulisp bootstrap` で Stage 2 → Stage 3 の自己コンパイル不動点（SHA-256 一致）を維持していること。
- [ ] 施策前後の計測値（自己コンパイル時間中央値 5 回・ELF/`.text` サイズ・`objdump` `[rsp]` 命令数）を本 Issue に記録していること。
- [ ] `verify-quality-gates` 全 PASS（相対リンクのみ・絶対パス 0 件）。

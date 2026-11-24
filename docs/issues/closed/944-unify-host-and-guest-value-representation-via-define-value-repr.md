---
ID: 944
種別: Feature
優先度: High
ステータス: Closed
担当エージェント:
  - IT Specialist (Programming Languages & Compilers / PLC) [Lead]
  - Systems Architect (SA)
  - Software Development (SWD)
  - Information Security Specialist
  - Software Quality Assurance Specialist
ターゲットブランチ: feat/944-unify-host-and-guest-value-representation
完了日: 2026-11-25
---

# [FEAT/ENH] Host / Guest 値表現の単一情報源化 (`define-value-repr` によるタグ操作・GC・プリンタの統一生成) (ID: 944)

## 1. 背景と課題 / Background & Problem Statement

現行コードベースでは、値表現（タグ定義・即値エンコーディング・ヒープポインタ境界・GC/プリンタ定数）が以下の 4 系統に分散・ハードコードされており、単一情報源（SSOT）が成立していない：

1. **[`ulisp/compiler/value_repr.scm`](../../../ulisp/compiler/value_repr.scm)（`define-value-repr` DSL）**:
   - `repr:scheme-64bit-tagged`（`fixnum: shift=2, mask=3`, `boolean: 47/111`, `null=63`, `eof=79`, `char: shift=8, tag=14`, `symbol: shift=6, tag=2, mask=255`, `pointer: align=8, pair=1, string=3, vector=5, bytevector=7, flonum=11`）・`repr:c-unboxed`・`repr:nan-boxing-64bit` を定義し、`ulisp/lir/129_lir_primitives.scm` および `ulisp/lir/131_lower_managed_dialect.scm` から参照されている。
   - しかし、`ulisp/runtime/`・`ulisp/backend/`・`ulisp/workbench/` からの参照が **0 件** であり、さらに [`ulisp/Makefile`](../../../ulisp/Makefile) の `COMPILER_BASE` 順で `workbench/value_tagging.scm` / `workbench/nan_boxing.scm` が `compiler/value_repr.scm` より先に結合されるため、ワークベンチ側が `define-value-repr` を参照できない状態にある。
2. **[`ulisp/workbench/value_tagging.scm`](../../../ulisp/workbench/value_tagging.scm) ＆ [`ulisp/workbench/nan_boxing.scm`](../../../ulisp/workbench/nan_boxing.scm)（Guest 値表現）**:
   - `value_tagging.scm` は 3-bit 動的タギング（`GUEST_TAG_FIXNUM=0` / `shift=3`, `GUEST_TAG_PAIR=1`, `GUEST_TAG_SYMBOL=2`, `GUEST_TAG_CLOSURE=3`, `GUEST_TAG_VECTOR=4`, `GUEST_TAG_INSTANCE=5`, `GUEST_TAG_FLONUM=6`, `GUEST_TAG_SPECIAL=7`, `GUEST_TAG_MASK=7`, `GUEST_SPECIAL_FALSE=0..UNDEF=3`）を独自定数として直書きしており、`value_repr.scm` に対応する `<value-repr>` 記述子（`repr:guest-3bit-tagged`）が存在しない。
   - `nan_boxing.scm` は `NAN_BOX_BASE`, `NAN_PAYLOAD_MASK`, `NAN_TAG_UNIT`, `NAN_TAG_FLONUM=0..POINTER=3` を独自定数として定義しており、`value_repr.scm` の `repr:nan-boxing-64bit` と二重管理になっている。
3. **[`ulisp/runtime/printer.scm`](../../../ulisp/runtime/printer.scm)（Host Pre-Scheme ランタイムプリンタ）**:
   - `*fixnum-mask*=3`, `*pair-tag*=1`, `*string-tag*=3`, `*vector-tag*=5`, `*bytevector-tag*=7`, `*char-tag*=14`, `*symbol-tag*=2`, `*bool-false*=47`, `*bool-true*=111`, `*empty-list*=63`, `*eof-object*=79` 等を独立に直書きしている。
4. **[`ulisp/backend/141_backend_x86_gc.scm`](../../../ulisp/backend/141_backend_x86_gc.scm) ＆ [`ulisp/backend/142_backend_x86_freestanding.scm`](../../../ulisp/backend/142_backend_x86_freestanding.scm)（バックエンド GC・ネイティブプリンタ）**:
   - `141_backend_x86_gc.scm` はヒープタグ判定（`and rax, 7`, `cmp rax, 1/3/5/7`, `and r8, -8`）およびエフェメロン真偽値（`47`, `111`）を直書きしている。
   - `142_backend_x86_freestanding.scm`（`ulisp_print_value`, `ulisp_read_char`, `ulisp_write_string` 等）は全タグ値（`3, 2, 47, 111, 63, 79, 14, 1, 3, 5, 7`）を `(current-value-repr)` から導出せず直接ハードコードしている。

ULisp 自身のランタイム（Host）もワークベンチ上のゲスト言語のランタイム（Guest）も「値表現仕様（`define-value-repr`）→ タグ操作・GC・プリンタ」という同一の自己相似構造を持つため、双方を `define-value-repr` から統一導出することで単一情報源（SSOT）化し、DSN-33-22 のフラクタル言語ワークベンチ構造を完成させる。

---

## 2. トレーサビリティと影響範囲 / Traceability & Scope

### 関連ドキュメント（すべて相対リンク）
- [DSN-33-22](../../designs/DSN-33-22-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
- [DSN-33-13](../../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- [Issue #836](836-plugin-value-representation-and-boxing-scheme.md)
- [Issue #893](893-implement-guest-dynamic-value-tagging-and-nan-boxing.md)

### 変更対象ファイル
- [x] [`ulisp/compiler/value_repr.scm`](../../../ulisp/compiler/value_repr.scm) (`repr:guest-3bit-tagged` 追加、`:bind-runtime-constants` マクロ展開、タグ操作・GC 判定・汎用プリンタ/コード生成 API 拡張)
- [x] [`ulisp/workbench/value_tagging.scm`](../../../ulisp/workbench/value_tagging.scm) (`repr:guest-3bit-tagged` からの定数・パック/アンパック/検査の統一導出)
- [x] [`ulisp/workbench/nan_boxing.scm`](../../../ulisp/workbench/nan_boxing.scm) (`repr:nan-boxing-64bit` からの NaN-boxing 定数・演算の統一導出)
- [x] [`ulisp/runtime/printer.scm`](../../../ulisp/runtime/printer.scm) (`(define-value-repr :bind-runtime-constants repr:scheme-64bit-tagged)` による SSOT 定数生成)
- [x] [`ulisp/backend/141_backend_x86_gc.scm`](../../../ulisp/backend/141_backend_x86_gc.scm) (`(current-value-repr)` による GC ヒープタグ・マスク・真偽値の動的参照)
- [x] [`ulisp/backend/142_backend_x86_freestanding.scm`](../../../ulisp/backend/142_backend_x86_freestanding.scm) (`(current-value-repr)` による `ulisp_print_value` 等ネイティブプリンタのタグ参照統一)
- [x] [`ulisp/compiler/module_header.scm`](../../../ulisp/compiler/module_header.scm) ＆ [`ulisp/Makefile`](../../../ulisp/Makefile) (`COMPILER_BASE` ロード順整備・新規エクスポート識別子登録)
- [x] [`ulisp/tests/test_value_representation.scm`](../../../ulisp/tests/test_value_representation.scm) ＆ [`ulisp/tests/test_workbench_tagging.scm`](../../../ulisp/tests/test_workbench_tagging.scm) (Host / Guest SSOT 一致・GC/プリンタ統一検証テスト追加)

---

## 3. セキュリティ・メモリ安全性要件 / Security & Safety Requirements

- **CWE-843 (Type Confusion Prevention)**: Host / Guest のタグ検査・アンパック・プリンタ・GC 判定は、必ず `validate-value-repr` を通過した `<value-repr>` 記述子からマスク・シフト・タグ値を導出し、定数不一致による型混同を構造的に根絶すること。
- **CWE-190 (Integer Overflow / Shift Bounds)**: `repr-pack-fixnum-checked` / `guest-pack-fixnum` / `nan-box-int32` は表現仕様の有効ビット幅（61-bit 符号付き等）を超えた場合に必ずエラーを送出すること。
- **CWE-119 (Heap Pointer Alignment & GC Copying)**: `repr-gc-heap-tags` が返す全ヒープタグ $t$ に対し $0 < t < \text{align}$ および $\text{untag-mask} = -\text{align}$ を満たし、未アラインポインタのタグ付けを拒否すること。
- **Bootstrap & Zero-Diff Invariant**: 既定値表現 `repr:scheme-64bit-tagged` の下で `141_backend_x86_gc.scm` および `142_backend_x86_freestanding.scm` が出力する x86-64 アセンブリは現行出力と完全一致し、3-stage モジュラーセルフホスト（`bootstrap_verify_modular`）が 0 diff で収束すること。

---

## 4. 実装計画 / Step-by-Step Implementation Plan

Target Branch: `feat/944-unify-host-and-guest-value-representation`

1. **Step 1 (`ulisp/Makefile` & `ulisp/compiler/value_repr.scm` — SSOT スキーマ＆統一ジェネレータ整備)**:
   - `ulisp/Makefile` の `COMPILER_BASE` で `compiler/value_repr.scm` を `workbench/value_tagging.scm` / `workbench/nan_boxing.scm` より先に配置する（依存循環がないことを確認済み）。
   - `ulisp/compiler/value_repr.scm` に Guest 標準の `repr:guest-3bit-tagged`（エイリアス: `guest-3bit-tagged`, `guest-tagged`）を `define-value-repr` で登録し、`:fixnum`（`:min`, `:max`）、`:immediates`（`:special-tag`, `:special-shift`, `:undef` 等）、`:pointer`（`:instance-tag`, `:symbol-ptr-tag`, `:gc-heap-tags` 等）および `:nan-box` の補助プロパティを整備する。
   - タグ操作・GC・プリンタ共通プリミティブを `value_repr.scm` に実装する：
     - タグ操作：`repr-pack-fixnum-checked`, `repr-unpack-fixnum-checked`, `repr-fixnum-val?`, `repr-pack-ptr-checked`, `repr-unpack-ptr-checked`, `repr-ptr-of-tag?`, `repr-extract-tag`, `repr-pack-special-val`, `repr-unpack-special-val`, `repr-special-val?`
     - GC 共通 API：`repr-gc-heap-tags`, `repr-gc-heap-value?`, `repr-gc-untag-ptr`
     - プリンタ / コード生成 API：`repr-format-tagged-value`（Host / Guest 両表現で即値・シンボル・文字・ポインタ種別を統一フォーマット）, `repr-synthesize-runtime-constants`
2. **Step 2 (`ulisp/workbench/value_tagging.scm` & `ulisp/workbench/nan_boxing.scm` — Guest 側統合)**:
   - `workbench/value_tagging.scm` の全定数（`GUEST_TAG_*`, `GUEST_SPECIAL_*`, `GUEST_FIXNUM_MAX/MIN`）および `guest-pack-*` / `guest-unpack-*` / `guest-*?` / emitter ヘルパを `repr:guest-3bit-tagged` と `value_repr.scm` API 経由に統一する（既存 API 互換と `stage-poly-lower` のタグ除去最適化を維持する）。
   - `workbench/nan_boxing.scm` の `NAN_BOX_BASE`, `NAN_PAYLOAD_MASK`, `NAN_TAG_UNIT`, `NAN_TAG_*` 等を `repr:nan-boxing-64bit` から導出する形へ統一する。
3. **Step 3 (`ulisp/runtime/printer.scm`, `141_backend_x86_gc.scm`, `142_backend_x86_freestanding.scm` — Host 側統合)**:
   - `ulisp/runtime/printer.scm` が `repr:scheme-64bit-tagged`（存在時）から `*fixnum-mask*`, `*pair-tag*`, `*string-tag*`, `*vector-tag*`, `*bytevector-tag*`, `*char-tag*`, `*symbol-tag*`, `*bool-false*`, `*bool-true*`, `*empty-list*`, `*eof-object*` 等を取得するよう統一し、単独ランタイムリンク時も不変整合を保つようにする。
   - `ulisp/backend/141_backend_x86_gc.scm` のポインタタグマスク（`repr-pointer-mask`）・アンタグマスク（`repr-pointer-untag-mask`）・GC 対象ヒープタグ一覧（`repr-gc-heap-tags`）・エフェメロン真偽値（`repr-encode-boolean`）を `(current-value-repr)` 駆動に置換する。
   - `ulisp/backend/142_backend_x86_freestanding.scm` の文字タグ/シフト、即値定数（`#f`, `#t`, `()`, `eof`）、ヒープタグ（`pair`, `string`, `vector`, `bytevector`）、シンボルマスク/タグをすべて `(current-value-repr)` から生成する。
   - 新規トップレベル定義を [`ulisp/compiler/module_header.scm`](../../../ulisp/compiler/module_header.scm) に追加する。
4. **Step 4 (`test_value_representation.scm` & `test_workbench_tagging.scm` — SSOT 検証テストと品質ゲート)**:
   - Host（`repr:scheme-64bit-tagged` / `runtime/printer.scm` / `141` / `142`）と Guest（`repr:guest-3bit-tagged` / `repr:nan-boxing-64bit` / `value_tagging.scm` / `nan_boxing.scm`）の全定数・タグ操作・`repr-gc-heap-value?`・`repr-format-tagged-value` が `define-value-repr` と 100% 一致することを検証するテストを追加する。

---

## 5. 完了条件 / Definition of Done (DoD)

- [x] **SSOT Convergence**: Host（`runtime/printer.scm`, `backend/141_backend_x86_gc.scm`, `backend/142_backend_x86_freestanding.scm`）および Guest（`workbench/value_tagging.scm`, `workbench/nan_boxing.scm`）のタグ定数・操作・GC 判定・プリンタが `define-value-repr`（`ulisp/compiler/value_repr.scm`）を単一情報源として一致していること。
- [x] **Polymorphic Tag / GC / Printer Verification**: `test_value_representation`・`test_workbench_tagging`・`test_gc_growth`・`test_gc_hybrid`・`test_gc_ephemeron`・`test_printer` がすべて PASS すること。
- [x] **Bootstrap Zero-Diff Invariant**: `make -C ulisp bootstrap_verify_modular` が stage2/stage3 ビット完全一致で収束すること。
- [x] **Quality Gates**: `python3 ulisp/scripts/lint_sexpr.py`、`verify_zero_gauche`、`make check_format`、`make static_analysis`、`make py_compile`、および相対リンク検証（絶対パス 0 件）がすべて PASS すること。

---

## 6. 完了サマリー / Completion Summary

- [`ulisp/Makefile`](../../../ulisp/Makefile) の `COMPILER_BASE` で `compiler/eval_in_language.scm` および `compiler/value_repr.scm` を `workbench/*` より先頭に配置し、コンパイル時・テスト時のロード順を統一。
- [`ulisp/compiler/value_repr.scm`](../../../ulisp/compiler/value_repr.scm) に `repr:guest-3bit-tagged`（エイリアス: `guest-3bit-tagged`, `guest-tagged`）、`(define-value-repr :bind-runtime-constants <repr>)` 静的定数展開、GC ヒープタグ照会/判定 API（`repr-gc-heap-tags`, `repr-gc-heap-value?`, `repr-gc-untag-ptr`）、汎用タグ付き値フォーマッタ（`repr-format-tagged-value`）を実装し、[`ulisp/compiler/module_header.scm`](../../../ulisp/compiler/module_header.scm) に公開識別子を登録。
- [`ulisp/workbench/value_tagging.scm`](../../../ulisp/workbench/value_tagging.scm)・[`ulisp/workbench/nan_boxing.scm`](../../../ulisp/workbench/nan_boxing.scm)・[`ulisp/runtime/printer.scm`](../../../ulisp/runtime/printer.scm)・[`ulisp/backend/141_backend_x86_gc.scm`](../../../ulisp/backend/141_backend_x86_gc.scm)・[`ulisp/backend/142_backend_x86_freestanding.scm`](../../../ulisp/backend/142_backend_x86_freestanding.scm) を `define-value-repr` 導出へ統一。
- `make -C ulisp bootstrap_verify_modular`（Stage 2 == Stage 3 全5モジュール 0 diff）・全関連テスト（`test_value_representation`, `test_workbench_tagging`, `test_printer`, `test_runtime`, `test_gc_ephemeron`, `test_gc_growth`, `test_gc_hybrid`, `test_lint_sexpr`, `verify_zero_gauche`）・`make check_format && make static_analysis && make py_compile` すべて PASS を確認。

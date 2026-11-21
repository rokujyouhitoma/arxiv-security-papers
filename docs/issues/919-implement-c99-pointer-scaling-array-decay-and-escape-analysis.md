---
ID: 919
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] C99 ポインタスケーリング演算・配列退化およびアドレス取得変数のスタックエスケープ処理の実装 (ID: 919)

## 1. 概要 / Summary
C99 の配列からポインタへの自動退化（Array-to-Pointer Decay）、ポインタ加減算の要素サイズ自動スケーリング（`ptr + n`, `p1 - p2`）、`.` / `->` メンバアクセス、および単項 `&` でアドレス取得されたローカル変数を SSA レジスタ昇格から保護しスタック上に留めるエスケープ解析・Lowering を実装する（Step S3 / T7）。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [DSN-33-32 §3.4, §4.1](../designs/DSN-33-32-ulisp_lua_c_codebase_compilation_and_self_hosting_architecture.md)
  - [DSN-33-13 §2.1, §4.1](../designs/DSN-33-13-ulisp_typed_machine_lir_and_multi_target_backend_architecture.md)
- 前提基盤 Issue: #827 (Braun SSA), #916, #918

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] `ulisp/frontend_c/sema.scm` (ポインタ演算型規則・配列退化・左辺値チェック)
- [ ] `ulisp/frontend_c/lower_to_lir.scm` (アドレス取得エスケープマーク・スケーリング加算・`%load`/`%store`)
- [ ] `ulisp/lir/132_braun_ssa.scm` (`%alloca` のうち非エスケープ変数のみを選択昇格)
- [ ] `ulisp/tests/test_c99_pointers_and_escape.scm` (新規: ポインタ演算・多次元配列・出力引数 `&status` テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/919-implement-c99-pointer-scaling-and-escape`

1. `sema.scm` にて配列式のポインタ型への暗黙退化、`ptr + idx` / `idx + ptr` / `ptr - idx` の型検証、およびポインタ減算 `p1 - p2` の `ptrdiff_t` 除算ノード生成を実装する。
2. `lower_to_lir.scm` にて変数がアドレス取得（`&var`）または配列型である場合に `:address-taken? #t` を記録し、Pass 132 Braun SSA がこれらの `%alloca` を誤って仮想レジスタへ昇格させないように制御する。
3. 構造体メンバや配列要素への間接参照（`p->field[i]`）のアドレスオフセット計算を最適な LIR 命令列へ降格する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 多次元配列、ポインタの前後置インクリメント（`p++`, `++p`）、ポインタ減算が C99 仕様通り動作すること。
- [ ] `&status` 等を別関数へ渡して書き換える出力引数パターンが Braun SSA 適用後も正しくメモリ経由で反映されること。
- [ ] 既存 Scheme テストおよび新規ポインタテストが全件 PASS すること。

---
ID: 626
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 3: S-RTyper 連携による完全アンボックス整数演算とタグ操作撲滅（Interprocedural Unboxing） (ID: 626)

## 1. 概要 / Summary
Pure C -O2 パリティ達成に向けた第 3 フェーズとして、**Fixnum 型タグ操作（シフト・マスク・検査）オーバーヘッドを撲滅し、生 64 ビット整数（Raw int64_t）レジスタ演算**を導入する（Issue #618 の成果と連携）。

現状の ULisp コンパイラでは、すべての数値が Scheme の Fixnum として 2 ビット左シフトタグ形式（`val << 2`）で扱われている。
加算・減算・比較のたびに、シフト操作（`sal / sar`）やタグ検査（`and $0x3`）が頻発し、CPU の ALU パイプラインを余分に占有している。

本 Phase 3 では、S-RTyper (Pass 090) の型推論結果を活用し、整数であることが証明された関数引数・戻り値・ローカル変数をネイティブ 64 ビット整数として直接扱い、演算命令を Pure C と同等のネイティブ命令列（`add`, `sub`, `cmp`）へと置換する。

---

## 2. トレーサビリティ / Traceability
- **先行 Phase Issues**:
  - [624-phase1-direct-known-function-calls.md](624-phase1-direct-known-function-calls.md) (Phase 1: 既知関数の直接呼出)
  - [625-phase2-system-v-register-based-calling-convention.md](closed/625-phase2-system-v-register-based-calling-convention.md) (Phase 2: System V レジスタ引数呼出規約)
- **関連 Issue**:
  - [618-eliminate-tagging-overhead-with-interprocedural-unboxing.md](618-eliminate-tagging-overhead-with-interprocedural-unboxing.md) (S-RTyper Pass 090 および LIR / バックエンドにおける関数間アンボックス特化)
- **後続 Phase Issue**:
  - [627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md](627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md) (Phase 4: ループ回転・末尾JMP・レジスタ割付とCパリティ検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm) (Pass 090: 整数型アノテーションの伝播)
- [ ] [ulisp/lir/129_lir_primitives.scm](../../ulisp/lir/129_lir_primitives.scm) (Pass 129: アンボックス算術プリミティブ `%unboxed-add`, `%unboxed-sub`)
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm) (Pass 130: アンボックス型命令の選択)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: 生 64-bit 算術命令出力、境界タグ付け)
- [ ] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (Phase 3 適用後の実行時間記録)

---

## 4. 具象的改善アプローチ / Technical Approach
1. **型推論情報の LIR 伝播**:
   - `fib` のシグネチャを `int64_t -> int64_t` と判定。
   - 再帰内部の呼出しはアンボックス引数・戻り値で結合。
2. **ALU 命令の単純化**:
   - `cmp rdi, 2` （従来の `cmp rdi, 8` から修正）
   - `dec rdi` （従来の `sub rdi, 4` から修正）
3. **入出力境界（REPL / Print）でのボクシング**:
   - 最終計算結果を表示する際のみ `sal rax, 2` で Fixnum 化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 再帰関数およびループ内の加減算・比較演算から `sar`, `sal`, `and 3` が消滅すること。
- [ ] `fib 30` の実行時間が Pure C -O2（約 3.9 ms）と同等の **< 4.2 ms（パリティ比率 1.1x 圏内）** に到達すること。
- [ ] 全テストスイートが 100% PASS すること。

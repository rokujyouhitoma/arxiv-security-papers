---
ID: 624
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 1: 既知関数の直接呼出最適化（Direct Known-Function Calls）とクロージャ呼出オーバーヘッドの撲滅 (ID: 624)

## 1. 概要 / Summary
Pure C -O2 に対する ULisp x86-64 ネイティブコードの性能格差（Fib 30 で 2.58x 遅延、Ack 3 7 で 6.41x 遅延）の最大要因である**「既知関数に対する間接クロージャ呼出し（Indirect Closure Call Overhead）」**を完全に排除する。

現状の ULisp コンパイラでは、`fib` や `ack` などの再帰呼出しにおいて、呼出し先がコンパイル単位内で静的に自明であるにもかかわらず、毎回クロージャオブジェクトから関数エントリポインタを取得し、間接呼出し（`call rdx`）を発行している：
```assembly
mov rdx, [r10 - 1]   ; クロージャオブジェクトからエントリポインタ取得
call rdx             ; 間接呼出し（BTBミス・パイプラインストール）
```
間接分岐は CPU の Branch Target Buffer (BTB) を逼迫させ、分岐予測ミスによる深刻なパイプラインフラッシュを引き起こしている。

本 Phase 1 では、静的解析によってコールターゲットが確定している関数（`known-function`）を特定し、間接呼出しを排除してアセンブリラベルへの直接呼出し（`call .L_fib_entry`）を出力する最適化パイプラインを確立する。

---

## 2. トレーサビリティ / Traceability
- **親ロードマップ**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 1 章 レジスタアーキテクチャ、第 6 章 LIR / 最適化パス)
  - [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (正典性能ベースライン測定レポート)
- **後続 Phase Issues**:
  - [625-phase2-system-v-register-based-calling-convention.md](625-phase2-system-v-register-based-calling-convention.md) (Phase 2: System V レジスタ引数呼出規約)
  - [626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md](626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md) (Phase 3: S-RTyper 連携アンボックス演算)
  - [627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md](627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md) (Phase 4: ループ回転・末尾JMP・レジスタ割付とCパリティ検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/110_closure_convert.scm](../../ulisp/frontend/110_closure_convert.scm) (Pass 110: 既知関数の検出と直接呼出アノテーション `%direct-call`)
- [ ] [ulisp/frontend/120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm) (Pass 120: 非エスケープクロージャのアロケーション回避)
- [ ] [ulisp/lir/123_lir_closures.scm](../../ulisp/lir/123_lir_closures.scm) (Pass 123: 直接呼出ノードの LIR 生成)
- [ ] [ulisp/lir/124_lir_call_abi.scm](../../ulisp/lir/124_lir_call_abi.scm) (Pass 124: 直接呼出ターゲットのシンボル解決)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: `call .L_...` 直接呼出命令の出力)
- [ ] [ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) (Phase 1 適用後の実行時間記録)

---

## 4. 具象的改善アプローチ / Technical Approach
1. **既知関数の静的識別 (Known-Function Analysis)**:
   - トップレベル関数、および `letrec` / `let` で定義され外部にファーストクラスオブジェクトとして脱出（escape）しない関数を Pass 110 で収集。
2. **中間表現への直接呼出命令の導入**:
   - `(%call-known target-label (args...))` または `(%direct-call label ...)` を導入。
   - クロージャオブジェクト構築（環境タプル生成）を省略可能にし、ヒープ消費を削減。
3. **x86-64 バックエンドでの直接ラベル呼出コード生成**:
   - 間接ロード（`mov rdx, [r10 - 1]; call rdx`）を廃止し、直接相対呼出 `call .L_target` を生成。
   - 分岐予測ミスをほぼゼロに抑制。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `fib` および `ack` の再帰呼出しにおいて `call rdx`（間接呼出）が完全消滅し、直接ラベル呼出（`call .L_...`）が出力されること。
- [ ] `fib 30` の実行時間がベースライン（10.09 ms）から 30% 以上短縮（< 7.0 ms）すること。
- [ ] `ack 3 7` の実行時間がベースライン（21.80 ms）から 40% 以上短縮（< 13.0 ms）すること。
- [ ] 既存の全テスト（Pass単体テスト、GCテスト、言語機能テスト）が 100% PASS すること。

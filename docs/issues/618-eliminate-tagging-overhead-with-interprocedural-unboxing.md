---
ID: 618
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] S-RTyper（Pass 090）および LIR / バックエンドにおける関数間アンボックス特化とタグオーバーヘッド撲滅 (ID: 618)

## 1. 概要 / Summary
現在 ULisp の S-RTyper（[frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm)）は、局所的な純粋末尾再帰ループ（`pure-tail-loop?`）内でのみ `%raw-i64` へのアンボックス化を行っている。しかし、関数呼び出し境界、コレクション走査（ベクタ・文字列）、および基本ブロック間の合流点（$\phi$ ノード）においては、依然として Scheme の汎用 Tagged Pointer 規約（64-bit 下位 3 ビットタグ）に縛られており、頻繁なタグ外し（`sar`）およびタグ付け（`sal` / `%box-fixnum`）の往復が発生している。

本 Issue では、局所ループに限定されていたアンボックス化をコンパイラ全体へと拡張する。具体的には、エスケープしない既知関数に対する「Unboxed Direct Call ABI（生レジスタ直接引数・返り値渡し）」の導入、Braun SSA（Pass 132）と連携したフロー依存型推論（Flow-Sensitive Type Propagation）、および x86-64 の 8 倍スケールアドレッシング特性を活かしたゼロコスト配列インデックス化を実装し、数値計算およびメモリ走査における C 言語（GCC -O2）との性能差を完全ゼロに収束させる。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 7 章・第 8 章)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 518: S-RTyper (Pass 090) 局所アンボクシングの導入
  - Issue 596: Backend層: define-language L_asm 導入による命令選択とコード生成の2段階分離
  - Issue 600: 統合シンボル・スコープ解決基盤および α 変換エンジンの導入
  - Issue 616: Scheme ネイティブ x86-64 マシン語エンコーダおよび ELF64 実行可能バイナリ直接出力バックエンドの実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/frontend/090_rtyper.scm](../../ulisp/frontend/090_rtyper.scm) (関数境界跨ぎのアンボックス型推論と Unboxed 関数シグネチャの登録)
- [ ] [ulisp/lir/124_lir_call_abi.scm](../../ulisp/lir/124_lir_call_abi.scm) (Unboxed ABI 呼出し規約の追加とスタック/レジスタ割当て)
- [ ] [ulisp/lir/132_lir_braun_ssa.scm](../../ulisp/lir/132_lir_braun_ssa.scm) (SSA $\phi$ ノードにおける型情報格子の伝播)
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (ゼロコスト Fixnum アドレッシング `[base + index * 8]` の命令選択)
- [ ] [ulisp/tests/passes/test_090_rtyper.scm](../../ulisp/tests/passes/test_090_rtyper.scm) (関数間アンボックス単体テストの拡充)
- [ ] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../ulisp/benchmarks/benchmark_c_vs_x86.py) (C 言語との実行速度ギャップ測定)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/618-eliminate-tagging-overhead-with-interprocedural-unboxing`

1. **既知関数（Known Functions）の Unboxed Direct Call ABI**:
   - トップレベルおよび `letrec` で定義された内部関数のうち、外部へエスケープしない関数を特定。
   - 引数と戻り値がすべて Fixnum である場合、ボクシングを行わず生 64bit 整数（`%raw-i64`）として汎用レジスタ（RDI, RSI, RDX, RCX, R8, R9, RAX）で直接受け渡す専用シンボルを生成。
2. **Braun SSA 連携による型伝播（Type Lattice）**:
   - 変数の型を束（$\bot \le \text{Fixnum} \le \top$）として表現し、条件分岐ガード（`fixnum?`, `<`, `=` 等）を通過したパスにおいて、変数の型情報を後続の基本ブロックへ伝播。
   - 合流点（$\phi$ 関数）で全先行ブロックが Fixnum であれば、ボクシング挿入をバイパス。
3. **ゼロコスト配列インデックス（Zero-Cost Addressing）**:
   - `vector-ref`, `string-ref` において、Tagged Fixnum（下位 3 ビット 0）をアンシフト（`sar 3`）してから 8 倍スケールする冗長な命令列を検知。
   - `[base + fixnum_reg]`（スケール 1 倍、オフセット補正）またはスケール命令を直接利用し、シフト命令を完全除去。
4. **回帰検証および性能測定**:
   - 既存の全 Nanopass テストおよびブートストラップが完全一致することを確認。
   - ベンチマーク（Fibonacci, Tak, Ackermann, 配列走査）において GCC `-O2` に対するオーバーヘッドが 5% 未満に達していることを確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 既知関数間の直接呼び出しにおいて、引数・戻り値の `%box-fixnum` / `%unbox-fixnum` が完全除去されること。
- [ ] 配列アクセス時、インデックス計算のための余分なシフト命令（`sar`）が発生しないこと。
- [ ] `make test_rtyper` および `make test` が 100% PASS すること。
- [ ] 3-Stage Bootstrap 固定点（Fixed Point）が正常に成立すること。
- [ ] 主要な数値計算ベンチマークにおいて GCC -O2 と同等の実行速度が実測確認されること。

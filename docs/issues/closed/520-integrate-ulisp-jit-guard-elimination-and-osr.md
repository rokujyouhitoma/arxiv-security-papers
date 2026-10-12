---
ID: 520
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] 静的型知識に基づく JIT ガード命令事前消去 (Guard Elimination) と OSR 復元コード合成の実装 (ID: 520)

## 1. 概要 / Summary
現在 `ulisp/jit/` で動作している内因的メタトレーシング JIT（旧 MLisp）は、ループ実行時に動的な型ガード命令（`%guard type-fixnum ...` 等）を挿入しているが、S-Annotator（Issue #517）の静的型知識と連携していないため、冗長なガードが大量に残存している。
本 Issue では、S-Annotator の型情報およびトレース内型推論を JIT 最適化パス（`ulisp/jit/optimizer/pe.scm` および `ulisp/driver/jit.scm`）に統合し、静的に型が確定している箇所のガード命令を事前消去（A-priori Guard Elimination）するとともに、万一投機が外れた場合の On-Stack Replacement (OSR) 脱出アダプタを自動合成することで、JIT ホットループの実行オーバーヘッドを最小化する。
また、ユーザー指示に基づき、最適化の適用前後で命令数・ガード数・ベンチマークスループットの事前事後計測（Baseline vs Post-Optimization）を厳格に実施・比較記録する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (AOT & JIT 統合アーキテクチャ 第7章)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-35: Continuous Benchmarking Framework](../../designs/DSN-35-ilisp_ulisp_aot_jit_continuous_benchmarking_framework.md)
- **関連先行 Issue**:
  - Issue #507: 限定継続と ULisp LIR に基づく内因的メタトレーシング JIT ツールチェーンの実装
  - Issue #510: MLisp によるループ構文の自動検知と jit-merge-point 自動計装機能の実装
  - Issue #517: ULisp コンパイラへの抽象解釈型推論器 (S-Annotator) と型格子 (Lattice) の実装
  - Issue #518: ULisp 低水準IR具象化器 (S-RTyper) とアンボクシングによるタグ検査完全消去

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/jit/optimizer/pe.scm](../../../ulisp/jit/optimizer/pe.scm) (型環境導入と `%guard` 事前消去パスの実装)
- [x] [ulisp/driver/jit.scm](../../../ulisp/driver/jit.scm) (スタンドアロン JIT ドライバ側のオプティマイザおよび OSR 合成統合)
- [x] [ulisp/jit/tracer/tracer.scm](../../../ulisp/jit/tracer/tracer.scm) (型付きトレース記録とガード生成の精緻化)
- [x] [ulisp/jit/bridge/to_lir.scm](../../../ulisp/jit/bridge/to_lir.scm) (OSR 脱出ハンドラおよび Typed LIR 変換)
- [x] [ulisp/tests/jit/test_guard_elimination.scm](../../../ulisp/tests/jit/test_guard_elimination.scm) (新規作成: ガード消去＆OSR単体テスト 18件 100% PASS)
- [x] [ulisp/Makefile](../../../ulisp/Makefile) (テストスイートおよびランナーへの新規テスト登録)
- [x] [ulisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py](../../../ulisp/benchmarks/benchmark_stage2_vs_ulisp_jit.py) (事前・事後ベンチマーク計測)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/520-ulisp-jit-guard-elimination-and-osr`

1. **ベースライン（事前）計測の記録**:
   - `demo` トレース内のガード数（Raw 5個、PE最適化後 4個、LIR 24命令）。
   - `test_jit` 実行時間および現行ベンチマークの数値取得。
2. **静的型環境の JIT エンジンへの注入**:
   - `jit-merge-point` が呼ばれる際、S-Annotator が付与した引数・環境の静的型マップ（または型格子情報）をメタトレーサへ伝達。
   - トレースのメタデータに `(%types ((var . fixnum) ...))` を保持。
3. **Guard 事前消去パスの実装 (`pe.scm`, `driver/jit.scm`)**:
   - 引数・中間演算結果の型が即値整数（`number?`）または型環境で `fixnum` と保証されている場合、トレースリストから対応する `(%guard type-fixnum ...)` 命令を完全に刈り込む。
   - ループ不変量となる境界チェック・述語ガードの畳み込み（Const folded guard removal）。
   - ドミネーティングガード伝播（同一ループ内で型検査済みの変数は以降の同一ガードを消去）。
4. **OSR（On-Stack Replacement）脱出アダプタの合成**:
   - 残存したガードが失敗した場合、アンボックスされた仮想レジスタを生整数から Tagged Pointer 形式へボクシング（`%sal reg 2`）して復元し、安全にインタプリタのフレームへ合流させる bailout アダプタブロックを `to_lir.scm` で合成。
5. **事後（Post-Optimization）計測と検証**:
   - 算術ループにおける型ガード数が 0 件に削減されたことを定量確認。
   - `make -C ulisp test_jit` の全 PASS 確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 事前（Baseline）と事後（Post-Optimization）の計測結果がドキュメントに明記されていること。
- [x] 算術演算ループ（`sum_loop`, `poly_loop`）の JIT トレースにおいて、自明なガード命令が 0 件に削減されること。
- [x] JIT トレースからの LIR 変換において、不要なガード判定（`bit-and`, `cmp`, `jump-if-zero` 等）の 24 命令が完全に消去されること。
- [x] OSR 脱出アダプタが正しく合成され、投機失敗時に状態が安全に復元されること。
- [x] `make -C ulisp test_jit` 全件（112 / 112 件: 94件 + 新規 test_guard_elimination 18件）が 100% PASS すること。

---

## 6. 計測結果 / Measurement Results (Baseline vs Post-Optimization)

ユーザー指示「事前事後で計測してください」に基づき、JIT 最適化適用前後の定量メトリクスを計測・比較した。

### 6.1 トレース内命令数およびガード命令数比較 (TinyVM 算術ループ: `make demo`)

| 評価項目 | 事前 (Baseline) | 事後 (Post-Optimization) | 削減率 / 改善効果 |
| :--- | :---: | :---: | :---: |
| **Raw トレース命令数** | 17 命令 | 17 命令 | - |
| **Raw トレース内ガード命令数** | 5 命令 (`type-fixnum`×4, `cmp-lt`×1) | 5 命令 | - |
| **PE 最適化後トレース命令数** | 16 命令 | **12 命令** | **-25.0% 削減** |
| **PE 最適化後残存型ガード数** | 4 命令 (未消去で残存) | **0 命令** | **-100.0% (完全消去)** |
| **PE 最適化後全ガード命令数** | 4 命令 | **0 命令** | **-100.0% (完全消去)** |
| **LIR 展開時型判定オーバーヘッド命令数** | 24 命令 (4 × 6命令) | **0 命令** | **-100.0% (24命令消去)** |

### 6.2 JIT テストスイート検証 (`make test_jit`)

| テストスイート | 事前 (Baseline) | 事後 (Post-Optimization) | 状態 |
| :--- | :---: | :---: | :---: |
| `test_delimcc` (限定継続) | 9 / 9 PASS | 9 / 9 PASS | PASS |
| `test_tracer` (メタトレーサ) | 20 / 20 PASS | 20 / 20 PASS | PASS |
| `test_auto_instrument` (自動計装) | 24 / 24 PASS | 24 / 24 PASS | PASS |
| `test_optimizer` (PE & Virtuals) | 14 / 14 PASS | 14 / 14 PASS | PASS |
| **`test_guard_elimination` (新規ガード消去＆OSR)** | 未実装 | **18 / 18 PASS** | **新規 PASS** |
| `test_bridge` (LIR ブリッジ) | 20 / 20 PASS | 20 / 20 PASS | PASS |
| `test_examples` (TinyVM / mini-eval) | 7 / 7 PASS | 7 / 7 PASS | PASS |
| **合計通過件数** | **94 / 94 (100%)** | **112 / 112 (100%)** | **+18件 拡充 (100% PASS)** |

### 6.3 OSR 脱出アダプタ検証
- **事前**: 未接続のラベルジャンプのみで、投機失敗時のインタプリタ合流コードが未生成。
- **事後**: 残存ガード発生時に仮想レジスタを生整数から Tagged Pointer 形式へボクシング（`%sal reg 2`）し、インタプリタのフレームへ安全に合流する OSR 脱出アダプタブロックを自動合成（`test_guard_elimination` Test 4 にて検証完了）。


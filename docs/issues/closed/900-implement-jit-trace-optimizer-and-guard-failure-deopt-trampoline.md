---
ID: 900
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Implement JIT Trace Optimizer and Guard-Failure Deopt Trampoline (ID: 900)

## 1. 概要 / Summary

[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 4 章および第 5 章に基づき、記録された JIT トレース（`%trace-loop`）に対する高度な最適化パイプライン（冗長ガード除去、仮想オブジェクト割り当て除去）およびガード失敗時のスタック・フレーム復元トランポリン（Deoptimization / OSR Bailout Trampoline & Re-materialization）を実装する。

本機能により、内因的メタトレーサが記録した生トレースから動的型チェックと一時オブジェクトのヒープ割り当てを極限まで排除（$O(0)$ Allocation）し、投機的ガード失敗時にもインタプリタの状態を完全に復元してシームレスに継続実行できる堅牢性を確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第4章 コアサブシステム詳細設計 / 第5章 単一自己完結バイナリ設計)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - [[DSN-33-04] ULisp ゲスト言語マルチターゲット実行基盤設計書 (第4章 FrameDescriptor)](../designs/DSN-33-04-ulisp_guest_language_meta_runtime_framework.md)
- 先行 Issue:
  - [Issue #898: 評価器ループに対する JIT マージポイントおよび型ガード注釈基盤の実装](closed/898-implement-jit-loop-merge-point-and-guard-annotations.md)
  - [Issue #899: ホットループ検出プロファイラおよび限定継続（shift/reset）線形トレースレコーダの実装](closed/899-implement-hot-loop-profiler-and-linear-trace-recorder.md)
- 後続 Issue:
  - [Issue #901: 最適化済み LIR トレースからインメモリ W^X 実行可能バッファへのネイティブ機械語直接アセンブル配線](901-integrate-jit-trace-buffer-with-in-memory-native-x86-emitter.md)

---

## 3. 影響範囲と対象ファイル / Scope and Affected Files

- [ulisp/jit/optimizer/pe.scm](../../ulisp/jit/optimizer/pe.scm): トレース部分評価・定数伝播・A-priori / Dominating Guard Elimination の拡充
- [ulisp/jit/optimizer/virtuals.scm](../../ulisp/jit/optimizer/virtuals.scm): エスケープ解析に基づく短寿命ペア・環境オブジェクトの仮想化（スカラー昇格）
- [ulisp/jit/runtime/deopt.scm](../../ulisp/jit/runtime/deopt.scm) **[新規作成]**: JIT ガード失敗時のスタック・フレーム復元、仮想オブジェクト再実体化（Re-materialization）、および脱出監視
- [ulisp/jit/runtime/jit_buffer.scm](../../ulisp/jit/runtime/jit_buffer.scm): Deopt トランポリン・ハンドラ連携とブラックリスト機能
- [ulisp/jit/bridge/to_lir.scm](../../ulisp/jit/bridge/to_lir.scm): LIR 変換時の Deopt スナップショット情報（復元メタデータ）埋め込み
- [ulisp/tests/jit/test_jit_optimizer.scm](../../ulisp/tests/jit/test_jit_optimizer.scm) **[新規作成]**: 最適化パスと Deopt トランポリンの包括的単体テスト
- [ulisp/Makefile](../../ulisp/Makefile): `test_jit_optimizer` ターゲットの追加と `test_jit` 統合

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE Mitigations)

| 脅威 / 脆弱性 | リスク要因 | 対策・緩和策 (Mitigation) |
| :--- | :--- | :--- |
| **CWE-674: Uncontrolled Recursion (Deopt Thrashing / Ping-Pong)** | ガードが頻繁に失敗する境界条件で、JIT 実行と Deopt インタプリタ復帰を無限ループしてスタックオーバーフローを引き起こす。 | 各トレースの PC ごとに `deopt-failure-count` を管理。閾値（例: 連続 3 回）を超えた場合は即座に対象トレースを無効化（ブラックリスト登録）し、インタプリタ実行を継続させる。 |
| **CWE-400: Uncontrolled Resource Consumption (Re-materialization DoS)** | 脱出時に仮想化されていた複合データ構造（循環参照や深い入れ子）を再実体化する際、過剰なメモリ確保によるヒープ枯渇。 | 再実体化の再帰深度リミット `*max-rematerialize-depth* = 32` を設定し、循環検出・深度超過時には安全にアボートする。 |
| **CWE-787 / CWE-125: Out-of-bounds Read/Write (Corrupted Frame Reconstruction)** | 機械語レジスタやスタックスロットの値をフレーム環境にマップする際、インデックス境界外アクセスや未束縛スロット参照によるメモリ破壊。 | `FrameDescriptor` に基づくスロット数・型タグ整合性アサーションを実施し、不正なスナップショットによる復元を遮断する。 |

---

## 5. 詳細設計とアーキテクチャ / Detailed Architecture

### 5.1 トレース最適化パイプライン (Trace Optimization Pipeline)

```
[%trace-loop (Raw Tracing Output)]
    │
    ▼
[Pass 1: Partial Evaluation & Constant Folding (pe.scm)]
  - 定数伝播 (Constant Propagation)
  - 静的算術畳み込み (Constant Folding)
  - 自明なガード削除 (Trivial Guard Elimination)
    │
    ▼
[Pass 2: Type Inference & Guard Elimination (pe.scm)]
  - 算術演算連鎖における型推論 (%add / %sub / %mul)
  - 先行支配ガードによる後続ガード除去 (Dominating Guard Elimination)
  - ループ不変ガードの重複除去
    │
    ▼
[Pass 3: Virtualization & Allocation Removal (virtuals.scm)]
  - Intra-trace エスケープ解析 (Escape Analysis)
  - 非エスケープ %cons / %alloc-pair を仮想変数記述子へ変換
  - %car / %cdr 参照を仮想レジスタアクセスへ書き換え ($O(0)$ allocation)
    │
    ▼
[Pass 4: Deopt Snapshot Embedding (to_lir.scm & deopt.scm)]
  - 残存ガード命令にスナップショットメタデータ（フレーム復元情報）を付加
  - 脱出時のレジスタ/スタック -> インタプリタ変数対応マップの生成
    │
    ▼
[%optimized-trace-loop] -> LIR Bridge -> Native Machine Code
```

### 5.2 ガード脱出とスタック復元トランポリン (Deoptimization Architecture)

1. **Deopt スナップショット構造**:
   ```scheme
   (%guard <cond-op> <arg1> <arg2>
           (%deopt-snapshot
             (%pc <interpreter-pc>)
             (%frame-vars ((x . %rax) (y . %rdx) (env . %stack-16)))
             (%virtual-objects ((pair-1 pair val-car val-cdr))))
           <bailout-label>)
   ```
2. **Deopt トランポリン処理シーケンス**:
   - 条件分岐不一致により `<bailout-label>` へジャンプ。
   - JIT ランタイム脱出ルーチンが呼び出され、機械語実行コンテキスト（レジスタ値およびスタックスロット）を取得。
   - 仮想オブジェクト再実体化（`rematerialize-virtual-objects`）を実行し、仮想化されていた `pair` などをヒープ上に再構成。
   - インタプリタの `FrameDescriptor` に従い、ローカル変数環境 `(var . val)` を完全復元。
   - インタプリタの継続 `fail-k` または評価器ループへ復帰し、何事もなかったかのように解釈実行を継続。

---

## 6. 実装計画 / Implementation Plan

Target Branch: `feat/900-implement-jit-trace-optimizer-and-guard-failure-deopt-trampoline`

### Step 1: `ulisp/jit/optimizer/pe.scm` の機能拡充
- ループ不変ガードの検知と、先行ガードと同一変数の反復ガード除去を強化。
- `%guard` 命令に対するスナップショット情報の透過的保持。

### Step 2: `ulisp/jit/optimizer/virtuals.scm` の機能拡充
- エスケープ解析におけるガード脱出時の仮想変数生存性追跡。
- 脱出時に復元が必要な仮想オブジェクトリスト（`virtual-env`）のエクスポート。

### Step 3: `ulisp/jit/runtime/deopt.scm` の新規実装
- `*jit-max-deopt-thrash* = 3` による CWE-674 防護。
- `*max-rematerialize-depth* = 32` による CWE-400 防護。
- `deopt-snapshot` からインタプリタ環境を復元する `restore-interpreter-frame` の実装。
- 仮想オブジェクトをヒープに再アロケーションする `rematerialize-virtuals` の実装。
- トレース無効化（ブラックリスト登録）API `deopt-blacklist-trace!` の実装。

### Step 4: `ulisp/jit/bridge/to_lir.scm` への Deopt アダプタ統合
- ガード脱出ラベルにスナップショットメタデータを紐付ける OSR Bailout Adapter 生成の精緻化。

### Step 5: 包括的検証テストスイート `ulisp/tests/jit/test_jit_optimizer.scm` の作成
- **Group 1**: 定数畳み込み・伝播および自明ガードの完全除去
- **Group 2**: 同一変数・支配関係にある型ガードの 100% 除去（Guard Elimination）
- **Group 3**: 非エスケープ一時ペアの仮想化とアロケーションゼロ（Allocation Removal）
- **Group 4**: ガード失敗時の Deopt トランポリンとインタプリタ環境復元
- **Group 5**: 仮想オブジェクトの再実体化（Re-materialization）
- **Group 6**: Deopt スラッシング抑止・ブラックリスト化（CWE-674 防護）

### Step 6: Makefile ターゲット追加と全体回帰テスト
- `ulisp/Makefile` に `test_jit_optimizer` を追加し、`test_jit` に包含。
- `make -C ulisp test_jit`、`make -C ulisp lint_sexpr verify_zero_gauche`、`make py_compile && make static_analysis` のパス。

---

## 7. 完了条件 / Definition of Done (DoD)

- [x] **支配ガード除去**: 同一変数に対する重複型ガードおよびループ不変ガードが 100% 除去されること。
- [x] **仮想化アロケーション除去**: トレース内で完結する一時ペアの `%cons` が完全に除去され、レジスタアクセスへ縮退されること。
- [x] **Deopt トランポリン**: ガード失敗時に正しい変数状態と再実体化オブジェクトを保持してインタプリタ実行へフォールバックできること。
- [x] **セキュリティ防護**: 連続 Deopt 失敗時にブラックリスト登録され、スラッシング（CWE-674）が防止されること。
- [x] **単体テスト 100% PASS**: `make -C ulisp test_jit_optimizer` が全グループ PASS すること（35 passed）。
- [x] **JIT 回帰テスト 100% PASS**: `make -C ulisp test_jit` の全テストが PASS すること（全9スイート PASS）。
- [x] **静的解析・品質ゲート**: `make -C ulisp lint_sexpr verify_zero_gauche`、`make py_compile && make static_analysis` が PASS すること。
- [x] **相対パス規則厳守**: ドキュメントおよびコード内で絶対パスが 0 件であること。

---

## 8. 実装完了報告 / Completion Summary

1. **JIT 最適化パイプラインの強化**:
   - `ulisp/jit/optimizer/pe.scm`: 支配ガード追跡機構（`condition-dominated?`, `bind-guard-cond`, `unbind-guard-conds`）を実装。型ガード（`type-fixnum`, `type-boolean`, `type-pair`, `type-string`）および同一比較ガード（`cmp-lt` 等）の冗長重複を 100% 除去。ガード内のスナップショットメタデータを透過的に保護。
   - `ulisp/jit/optimizer/virtuals.scm`: エスケープ解析に基づく短寿命ペアの仮想化（$O(0)$ Allocation）と、脱出時再構成用の仮想オブジェクトマップ（`v-map` / `%virtual-objects`）エクスポートを実装。
2. **Deopt トランポリンとスタック復元ランタイム**:
   - `ulisp/jit/runtime/deopt.scm`: ガード失敗時のスタック・フレーム復元トランポリン（`restore-interpreter-frame`）、仮想オブジェクト再実体化（`rematerialize-virtual-value`, `rematerialize-virtuals`）、CWE-674 防護のスラッシング検知・自動ブラックリスト機能（`record-deopt-failure!`, `deopt-blacklist-trace!`）、CWE-400 防護の再帰深度上限（`*max-rematerialize-depth* = 32`）を実装。
   - `ulisp/jit/runtime/jit_buffer.scm`: ブラックリスト登録済み PC に対する JIT 実行回避・インタプリタフォールバック連携を配線。
   - `ulisp/jit/bridge/to_lir.scm`: トレース LIR 変換時にガード内スナップショットを自動登録する `register-trace-deopt-snapshots!` を統合。
3. **包括的検証テストスイート**:
   - `ulisp/tests/jit/test_jit_optimizer.scm`: Group 1〜6（35 テスト項目）を実装し、全項目 PASS を確認。


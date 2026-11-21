---
ID: 892
種別: Feature
優先度: High
ステータス: Closed (完了日: 2026-11-21)
---

# [FEAT/ENH] Implement Guest Frame Descriptor and Local Slot Lowering (ID: 892)

## 1. 概要 / Summary
[[DSN-33-04]](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md) 第 2 章（ゲスト言語オブジェクトモデル ＆ ランタイムフレーム抽象）に基づき、言語ワークベンチにおいてゲスト言語の変数環境を Scheme ネイティブの連想リスト探索（`assq`）から静的スタックフレーム記述子（`FrameDescriptor`）および固定オフセット（Local Slots）へコンパイル時降格するメカニズムを実装する。

ナイーブなインタプリタでは、変数束縛を `((x . 10) (y . 20))` のような連想リストとして動的に操作するため、部分評価器を通しても動的スコープや未解決の再帰呼び出しにおいて大量のペア確保・線形探索が残余コードに残存する。本 Issue では、GraalVM/Truffle の `FrameDescriptor` に着想を得た `<guest-frame-descriptor>` を導入し、変数参照を $O(1)$ の配列インデックス参照 `(frame-ref frame slot_idx)` または LIR 仮想レジスタへ 100% 降格させることで、実行時アロケーションをゼロにする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書:
  - [[DSN-33-04] ULisp 言語ワークベンチ・インタプリタ自動生成 ＆ ゲスト言語ランタイムアーキテクチャ設計書 (第2章 ゲスト言語オブジェクトモデル ＆ ランタイムフレーム抽象)](../designs/DSN-33-04-ulisp_language_workbench_interpreter_generator_and_guest_runtime_architecture.md)
  - [[DSN-33-03] ULisp ステージ多相メタコンパイラ ＆ 二村射影フラクタル実行基盤設計書 (第3.3節 Later 辞書)](../designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-01] ULisp 階層型パス融合 ＆ DAG 最適化基盤設計書](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/workbench/frame.scm](../../ulisp/workbench/frame.scm) (新規: FrameDescriptor レコードおよび静的スロット割り当てエンジン)
- [x] [ulisp/compiler/eval_in_language.scm](../../ulisp/compiler/eval_in_language.scm) (多相環境操作インターフェース・stage-poly-lower への降格フック統合)
- [x] [ulisp/tests/test_workbench_frame.scm](../../ulisp/tests/test_workbench_frame.scm) (新規: 単体・残余コード検証テスト)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (テストターゲット統合)
- [x] [docs/issues/README.md](README.md) (Issue 台帳ステータス更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/892-implement-guest-frame-descriptor-and-local-slot-lowering`

### Phase 1: `<guest-frame-descriptor>` データ構造とコンビネータ実装 (`ulisp/workbench/frame.scm`)
1. `<guest-frame-descriptor>` レコード型を定義：
   ```scheme
   (define-record-type <guest-frame-descriptor>
     (make-guest-frame-descriptor num-slots slot-names slot-types escape-mask)
     guest-frame-descriptor?
     (num-slots   gfd-num-slots)    ; スロット総数 (Fixnum)
     (slot-names  gfd-slot-names)   ; 変数名リスト (List of Symbols)
     (slot-types  gfd-slot-types)   ; 静的型ヒント (Vector of Types)
     (escape-mask gfd-escape-mask)) ; エスケープフラグ (クロージャ捕獲されるスロット)
   ```
2. スロット操作 API 群を実装：
   - `(gfd-empty)`: 空のフレーム記述子を生成。
   - `(gfd-add-slot! gfd name type-hint)`: 新規変数名を登録し、割り当てられたスロット番号（0-indexed）を返却。
   - `(gfd-lookup-slot gfd name)`: 変数名から静的スロットインデックスを取得（存在しない場合は `#f`）。
   - `(gfd-mark-escape! gfd slot-idx)`: クロージャ等に捕捉されるスロットにエスケープビットを付与。

### Phase 2: 静的フレーム環境（`<guest-frame-env>`）の構築
1. 連想リスト `((var . val) ...)` の二重化：
   - コンパイル時（Now）: 変数名から静的スロットインデックスへの解決マップ。
   - 実行時（Later）: 固定長ベクタ `(vector ...)` またはスタックフレーム上のスロット配列。
2. 環境参照コンビネータ `guest-env-ref`：
   - 静的にスロットインデックスが解決可能な場合、直接 `(vector-ref frame <idx>)` または `(local-slot-ref <idx>)` を出力。

### Phase 3: `stage-poly-lower` への降格フック統合 (`ulisp/compiler/eval_in_language.scm`)
1. `stage-poly-lower` 内の環境ルックアップ処理において、静的環境が `<guest-frame-descriptor>` を保持している場合、連想リスト探索関数呼び出し（`assq`）をインターセプト。
2. 残余 ANF 生成時に、不要なリスト操作を除去し、`vector-ref` / `local-slot-ref` 命令へダイレクトに降格。
3. エスケープマスクが 0 の非エスケープ変数については、LIR レベルの仮想レジスタ束縛（`let`）へ直結。

### Phase 4: テストスイートの実装と残余コード検証 (`ulisp/tests/test_workbench_frame.scm`)
1. マイクロ言語評価器を用意し、複数のローカル変数（`x`, `y`, `z`）を定義・参照するプログラムを実行。
2. 出力された残余 AST / LIR を検査し、以下の項目をアサーション検証：
   - 残余コード内に `assq`、`pair?`、`cons` が 1 つも含まれないこと。
   - 変数アクセスが全て `vector-ref` またはローカル仮想レジスタ転送命令になっていること。
   - 実行結果が元のリファレンス評価器と 100% 一致すること。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `<guest-frame-descriptor>` レコード型および操作 API 群が `ulisp/workbench/frame.scm` に実装されていること。
- [x] スロット名からインデックスへの $O(1)$ 解決が正常に機能すること。
- [x] `stage-poly-lower` との連携により、ゲスト言語の変数探索が連想リスト探索から静的スロット参照へ 100% 降格されること。
- [x] エスケープしない変数が LIR 上で仮想レジスタへ直接マッピングされること。
- [x] `make -C ulisp test_workbench_frame` が PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。
- [x] [docs/issues/README.md](README.md) のステータスが更新されていること。



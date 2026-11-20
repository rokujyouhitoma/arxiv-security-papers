---
ID: 883
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] freeze! 循環グラフ直列化と .rodata 肥大化ガードの実装 (ID: 883)

## 1. 概要 / Summary
DSN-33-03 §7.3 に基づき、Control Plane から Data Plane への境界変換 `freeze!` において、訪問済みセット（Visited Identity Map）を用いて循環参照・自己参照データ構造を無限ループせずに直列化する。また、直列化サイズが上限しきい値 `*max-rodata-size*`（64MB）を超過した場合にコンパイル時エラー `E-RODATA-OVERFLOW` を送出し、バイナリの無秩序な肥大化を防止する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §7.3 (境界データ変換 freeze!, 循環グラフ直列化, .rodata 上限チェック)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#73-境界データ変換freeze-循環グラフ直列化-rodata-上限チェック)
  - [DSN-33-02 §4 (Binary Representation & Sections)](docs/designs/DSN-33-02-ulisp_nanopass_ir_instruction_set_architecture.md)
- 関連 Issue:
  - #830 (ELF sections)
  - #839 (.sbi v2 IR serialization engine)
  - #884 (Data Plane 境界の Tag Stripping と 64-bit 単一ワード正規化)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/sbi.scm](ulisp/compiler/sbi.scm) - `freeze!`, 循環解決 DFS, `*max-rodata-size*` ガードの実装
- [x] [ulisp/tests/test_freeze_graph_rodata.scm](ulisp/tests/test_freeze_graph_rodata.scm) - 循環グラフ直列化およびサイズ上限ガード単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_freeze_graph_rodata` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/883-implement-freeze-graph-serialization-and-rodata-guard`

### 4.1 循環グラフ直列化 `freeze!`
1. **Visited Identity Map による閉路検出**:
   - オブジェクト走査時に各参照ノードの ID を訪問済み連想リストに登録。
   - 既に探索中のノードを再訪した場合は、後退エッジを `(cycle-ref <id>)` プレースホルダへ変換し、DFS の無限再帰を遮断。
2. **不変凍結**:
   - 走査完了後、オブジェクトを不変な静的定数表現（`.rodata` 向け DAG）として確定。

### 4.2 `.rodata` 肥大化ガード `*max-rodata-size*`
- 直列化バイト数（またはワード数×8）を追跡。
- `(freeze-serialize-to-rodata obj [max-size])` において累計サイズが `*max-rodata-size*`（デフォルト 64MB = 67,108,864 bytes）を超過した場合、`E-RODATA-OVERFLOW` エラーを送出。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 循環リストおよび自己参照構造がハングアップせず確実に直列化・復元できること。
- [x] サイズが上限しきい値を超過した際に `E-RODATA-OVERFLOW` エラーが確実に送出されること。
- [x] `make -C ulisp test_freeze_graph_rodata` が 0件エラー PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。

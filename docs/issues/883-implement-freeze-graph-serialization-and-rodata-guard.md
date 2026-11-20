---
ID: 883
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] freeze! 循環グラフ直列化と .rodata 肥大化ガードの実装 (ID: 883)

## 1. 概要 / Summary
DSN-33-03 §7.3 に基づき、Control Plane から Data Plane への境界変換 `freeze!` において、訪問済みセット（Visited Identity Map）を用いて循環参照・自己参照データ構造を無限ループせずに直列化する。また、直列化サイズが上限しきい値 `*max-rodata-size*`（64MB）を超過した場合に安全停止するバイナリ肥大化ガードを実装する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §7.3](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#73-境界データ変換freeze-循環グラフ直列化-rodata-上限チェック)
- 関連 Issue: #830 (ELF sections)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/sbi.scm](ulisp/compiler/sbi.scm)
- [ ] [ulisp/backend/144_linker.scm](ulisp/backend/144_linker.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/883-implement-freeze-graph-serialization-and-rodata-guard`

1. DFS 走査に Visited Map を導入し、循環リスト・自己参照ベクタの前方参照パッチングを実装。
2. `.rodata` セクション直列化バッファの累積サイズを追跡し、64MB 超過時に `E-RODATA-OVERFLOW` を送出。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 循環データ構造がハングアップせず `.rodata` へ直列化できること。
- [ ] サイズ超過時に安全停止すること。
- [ ] `make py_compile` が PASS すること。

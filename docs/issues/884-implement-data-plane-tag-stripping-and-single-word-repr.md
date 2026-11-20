---
ID: 884
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Data Plane 境界の Tag Stripping と 64-bit 単一ワード正規化の実装 (ID: 884)

## 1. 概要 / Summary
DSN-33-03 §7.3 および §4.2 に基づき、Control Plane の内部型付き共用体表現から、Restricted Data Plane で高速実行可能な 64-bit 単一ワード（上位ポインタ、下位 3-bit 型タグ）への脱タグ化（Tag Stripping）とデータレイアウト正規化を実装する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-33-03 §7.3](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#73-境界データ変換freeze-循環グラフ直列化-rodata-上限チェック)
- 関連 Issue: #826 (Typed LIR), #836 (Value Representation)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/value_repr.scm](ulisp/compiler/value_repr.scm)
- [ ] [ulisp/lir/131_lower_managed_dialect.scm](ulisp/lir/131_lower_managed_dialect.scm)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/884-implement-data-plane-tag-stripping-and-single-word-repr`

1. 静的定数および降格値に対し、下位 3-bit タグ（Fixnum: 0b1, Pair: 0b010 等）を直接エンコード。
2. LIR レベルで型検査命令を消去し、生のアセンブリメモリアクセスへと還元。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] Data Plane 上で実行されるコードに型タグ検査オーバーヘッドが生じないこと。
- [ ] `make py_compile` が PASS すること。

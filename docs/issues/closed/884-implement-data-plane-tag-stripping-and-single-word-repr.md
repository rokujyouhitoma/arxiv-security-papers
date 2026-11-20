---
ID: 884
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] Data Plane 境界の Tag Stripping と 64-bit 単一ワード正規化の実装 (ID: 884)

## 1. 概要 / Summary
DSN-33-03 §7.3 および §4.2 に基づき、Control Plane の内部型付き共用体表現から、Restricted Data Plane で高速実行可能な 64-bit 単一ワード（上位ポインタ、下位 3-bit 型タグ）への脱タグ化（Tag Stripping）とデータレイアウト正規化を実装する。また、静的に型確定した Data Plane コードにおいて型検査命令（`%bit-and`, `%cmp`, `%set-boolean`）を消去し、生ポインタへの直接メモリアクセスへと還元する。

---

## 2. トレーサビリティ / Traceability
- 関連個別仕様書:
  - [DSN-33-03 §7.3 (境界データ変換、Tag Stripping と 64-bit 単一ワード正規化)](docs/designs/DSN-33-03-ulisp_stage_polymorphic_metacompiler_and_futamura_projection_architecture.md#73-境界データ変換freeze-循環グラフ直列化-rodata-上限チェック)
  - [DSN-33-02 §5.1 (Value Representation & Boxing Engine)](docs/designs/DSN-33-02-ulisp_nanopass_ir_instruction_set_architecture.md)
- 関連 Issue:
  - #826 (Typed LIR)
  - #836 (Value Representation)
  - #883 (`freeze!` 循環グラフ直列化と `.rodata` 肥大化ガード)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/value_repr.scm](ulisp/compiler/value_repr.scm) - `data-plane-pack-word`, `data-plane-strip-tag`, `optimize-dataplane-tag-stripping` の実装
- [x] [ulisp/tests/test_dataplane_tag_stripping.scm](ulisp/tests/test_dataplane_tag_stripping.scm) - ワードパッキング・脱タグ化・冗長型検査消去の単体テスト
- [x] [ulisp/Makefile](ulisp/Makefile) - `test_dataplane_tag_stripping` ターゲット追加
- [x] [docs/issues/README.md](docs/issues/README.md) - 台帳ステータス更新

---

## 4. 詳細設計と実装方針 / Implementation Plan
Target Branch: `feat/884-implement-data-plane-tag-stripping-and-single-word-repr`

### 4.1 64-bit 単一ワード正規化 & 脱タグ化
1. **`data-plane-pack-word ptr tag`**:
   - 上位 61 ビットに 8 バイト境界アラインされたメモリアドレス、下位 3 ビットに型タグ（0〜7）をパッキング。
2. **`data-plane-strip-tag word`**:
   - 下位 3 ビットをマスク（`bitwise-and word -8`）して生ポインタアドレスを瞬時に復元。
3. **`data-plane-extract-tag word`**:
   - 下位 3 ビット（`bitwise-and word 7`）から型タグを抽出。

### 4.2 LIR レベルの型検査命令消去
- 静的に型が判明している（Now / BTA Static）変数へのアクセスにおいて、不要な型タグ検査命令列（`%bit-and`, `%cmp`, `%set-boolean`）を検出して消去。
- 直後の `%branch-if` を無条件ジャンプまたは直接インラインコードへ折り畳む。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] 64-bit ワードパッキングおよび Tag Stripping（脱タグ化）が 100% 正確に動作すること。
- [x] Data Plane 上で静的に型確定したアクセスに対する型検査命令が確実に消去されること。
- [x] `make -C ulisp test_dataplane_tag_stripping` が 0件エラー PASS すること。
- [x] `make py_compile && make static_analysis` が PASS すること。

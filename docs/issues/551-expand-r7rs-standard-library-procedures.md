---
ID: 551
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS 標準シーケンス操作・変換手続き群 (vector-copy / list-copy / string-copy! 等) の拡充 (ID: 551)

## 1. 概要 / Summary
R7RS-small (Section 6.7〜6.9) で規定されているが現在 ULisp に欠落しているシーケンス（リスト、ベクタ、文字列、バイトベクタ）関連の標準手続き群を一括拡充する。
これらの関数群は低レベルコンパイラ（LIR や x86 アセンブリ生成）に手を加える必要がなく、既存の `vector-ref`, `vector-set!`, `make-vector`, `string-ref`, `string-set!` 等を組み合わせた純粋 Scheme 手続き（`ulisp/lib/` 配下）として安全かつ即座に実装できる。これにより、一般的な Scheme ライブラリやコード資産の ULisp への移植性を飛躍的に高める。

---

## 2. トレーサビリティ / Traceability
- **規格仕様**:
  - R7RS-small Section 6.4 "Pairs and lists" (`list-copy`, `make-list`)
  - R7RS-small Section 6.7 "Strings" (`string-copy!`, `string-fill!`, `string-map`, `string-for-each`)
  - R7RS-small Section 6.8 "Vectors" (`vector-copy`, `vector-copy!`, `vector-append`, `vector->list`, `list->vector`, `vector-fill!`, `vector-map`, `vector-for-each`)
  - R7RS-small Section 6.9 "Bytevectors" (`bytevector-copy`, `bytevector-copy!`, `bytevector-append`)
- **設計仕様書**: [DSN-33 (ULISP 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/vector.scm](../../ulisp/lib/vector.scm) (新規作成または拡充: ベクタ操作手続き)
- [ ] [ulisp/lib/string.scm](../../ulisp/lib/string.scm) (文字列操作手続き拡充)
- [ ] [ulisp/lib/bytevector.scm](../../ulisp/lib/bytevector.scm) (バイトベクタ操作手続き拡充)
- [ ] [ulisp/lib/list.scm](../../ulisp/lib/list.scm) (リスト操作手続き拡充)
- [ ] [ulisp/compiler.scm](../../ulisp/compiler.scm) (プリロード設定)
- [ ] [ulisp/tests/test_stdlib_r7rs.scm](../../ulisp/tests/test_stdlib_r7rs.scm) (新規作成: 標準手続き包括テスト)
- [ ] [ulisp/test.sh](../../ulisp/test.sh) / [ulisp/test_c.sh](../../ulisp/test_c.sh) (テストスイート実行)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/551-expand-r7rs-standard-library-procedures`

1. **対象手続きの実装リスト**:
   - **リスト**: `list-copy`, `make-list`
   - **ベクタ**:
     - `vector-copy`, `vector-copy!`, `vector-append`
     - `vector->list`, `list->vector`
     - `vector-fill!`, `vector-map`, `vector-for-each`
   - **文字列**:
     - `string-copy!`, `string-fill!`, `string-map`, `string-for-each`
   - **バイトベクタ**:
     - `bytevector-copy`, `bytevector-copy!`, `bytevector-append`
2. **境界検査とスライシング最適化**:
   - `start`, `end` 省略可能引数（オプショナル引数）のハンドリング。
   - `vector-copy!` 等におけるオーバーラップコピー（メモリ重なり）の考慮。
3. **テスト検証**:
   - 部分コピー、範囲外アクセスエラー、相互変換（`vector->list` / `list->vector`）の往復性、破壊的代入の整合性確認。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 上記すべての R7RS 標準手続きが定義され、エッジケースを含めて期待通り動作すること
- [ ] オプショナル引数（`start`, `end`）のデフォルト値解決が正しく機能すること
- [ ] x86-64 および Portable C の両バックエンドで動作すること
- [ ] `make test`, `make test_c`, `make bootstrap` が 100% PASS すること

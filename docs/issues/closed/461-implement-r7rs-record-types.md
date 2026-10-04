# Issue #461: R7RS レコード型機構の実装 (`define-record-type`)

## 1. 概要 (Overview)
R7RS-small 第5.5節「Record-type definitions」に準拠した型安全なレコード型（構造体）定義機構 `define-record-type` および関連プリミティブを ILISP ランタイム・評価器・Python AST コンパイラ (Backend A) に実装した。
レコード型は、プログラマが名前付きフィールドを持つ直積型（Disjoint Type）を新たに定義し、コンストラクタ、型述語、フィールドアクセサ、フィールドモディファイアを自動生成・カプセル化する Scheme の基礎機構である。

## 2. 背景・動機 (Background & Motivation)
- **R7RS 準拠性の向上**: R7RS コア仕様において `define-record-type` は `(scheme base)` の中核機能であり、現在未実装（計画中）となっていた。
- **データ抽象と型安全性**: 従来の連想リスト (alist) やベクタに依存したデータ表現から、独立した型タグと名前付きフィールドを持つレコード型への昇格により、大規模プログラムやコンパイラ内部データ構造（AST ノード、トークン等）の堅牢性が向上した。
- **Python 相互運用性**: Python 側からも属性アクセス可能な `Record` 型として実装することで、ILISP と Python 間のシームレスなデータ交換を支援する。

## 3. 要件仕様 (Requirements Specification)
### 3.1 構文仕様 (Syntax)
```scheme
(define-record-type <type-name>
  (<constructor> <initial-field-name> ...)
  <predicate>
  <field-spec> ...)
```
各 `<field-spec>` は以下のいずれかの形式：
1. `(<field-name> <accessor-name>)` （イミュータブルフィールド）
2. `(<field-name> <accessor-name> <modifier-name>)` （ミュータブルフィールド）

### 3.2 動作仕様 (Semantics)
1. **型記述子 (Record Type)**:
   - `<type-name>` に一意な型記述子オブジェクト（または識別シンボル）を束縛。
   - `record?` 汎用述語および `<predicate>` 特定型述語。
2. **コンストラクタ**:
   - `(<constructor> arg ...)` を呼ぶと、`<initial-field-name> ...` に渡された引数が対応するフィールドに設定され、指定外のフィールドは `#f`（または未定義値）で初期化された新しいレコードインスタンスを返却。
3. **述語**:
   - `(<predicate> obj)` は `obj` が `<type-name>` のレコードインスタンスであれば `#t`、それ以外は `#f` を返却。
4. **アクセサ**:
   - `(<accessor-name> record)` は当該レコードの指定フィールド値を返却。対象外オブジェクトが渡された場合は `TypeError` 送出。
5. **モディファイア**:
   - `(<modifier-name> record new-val)` は当該レコードの指定フィールドを破壊的に更新。
6. **低レベルプリミティブ**:
   - `make-record-type`, `record-type?`, `record?`, `record-type`, `record-type-name`, `record-type-field-names`, `make-record`, `record-ref`, `record-set!`, `record-predicate`, `record-accessor`, `record-modifier`, `record-constructor` を完備。

## 4. 影響範囲・対象ファイル (Target Files)
- `ilisp/types.py`: `RecordType`, `Record` クラスの追加、型判定・文字列表現
- `ilisp/env.py`: 低レベルレコード操作プリミティブ (`record?`, `make-record-type`, `record-constructor`, `record-predicate`, `record-ref`, `record-set!`, `record-type` 等) の環境登録、`equal?` 比較処理
- `ilisp/evaluator.py`: 自己評価リテラルへの `Record`, `RecordType` 追加
- `ilisp/stdlib/base.ilisp`: `define-record-type` 構文の標準マクロ展開
- `ilisp/backend/py_codegen/compiler.py`: Backend A における `Record`, `RecordType` インポートと実行時名前空間連携
- `tests/ilisp/test_record_type.py`: 新規テストスイート作成（構築、アクセサ、ミューテータ、型チェック、エラー処理、トランスパイラ連携）
- `ilisp/docs/SPEC_R7RS.md`: 第5.5節および第6章のレコード関連ステータス更新

## 5. DoD (Definition of Done)
- [x] `define-record-type` 構文によりコンストラクタ、型述語、アクセサ、ミューテータが正しく定義できる。
- [x] イミュータブルフィールドおよびミュータブルフィールドの双方が正しく動作する。
- [x] 異なるレコード型同士、および他型（ベクタ、ペア等）との型排他性 (`predicate?`) が成立する。
- [x] 無効な引数（型不一致、引数過不足）に対して適切なエラーが送出される。
- [x] Backend A (Python AST トランスパイラ) でレコード定義・生成・アクセスが等価に実行できる。
- [x] `pytest tests/ilisp` 全件成功 (187 passed)。
- [x] `flake8` 0 警告、`mypy --strict` 0 エラー。
- [x] `ilisp/docs/SPEC_R7RS.md` の準拠マトリクス更新。

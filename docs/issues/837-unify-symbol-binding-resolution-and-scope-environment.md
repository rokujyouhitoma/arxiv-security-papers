---
ID: 837
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT] 構文解析後の一意束縛解決 (Binding ID) とスコープ環境管理の共通基盤化 (ID: 837)

## 1. 概要 / Summary
フロントエンドの構文解析直後（Early Phase）において、すべての変数・識別子を「文字列/シンボル」から一意な束縛オブジェクト（`<binding-id>` + 属性メタデータ）へと解決する共通のレキシカルスコープ管理・α変換（Alpha Conversion）基盤を構築する。
C 言語の名前空間（通常の変数・関数名、構造体/共用体タグ名、ラベル、typedef 名、ブロックスコープのシャドウイング）と、Scheme の衛生的マクロ展開（Scope Sets）を統一的な「レキシカルスコープ木と識別子解決」としてモデル化し、Lowering 以降の後続パスにおいて変数名の衝突やシャドウイングの考慮を一切不要化する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (B3: 構文解析・lexer hack, B4: 意味解析), フロントエンド共通基盤
- **関連 Issue**: #824 (Source Span), #825 (AST Evaluator)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/binding.scm](../../ulisp/compiler/binding.scm): 束縛レコード（Binding ID、可視性、型属性、ストレージクラス）の定義
- [ ] [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm): レキシカルスコープ木、ルックアップ、シャドウイング解決エンジン
- [ ] [ulisp/compiler/020_parse.scm](../../ulisp/compiler/020_parse.scm): 構文解析後の α 変換フェーズの組み込み
- [ ] [ulisp/tests/test_scope_and_binding.scm](../../ulisp/tests/test_scope_and_binding.scm): 多重ブロックスコープおよび名前解決テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/837-unified-symbol-binding-resolution`

1. 束縛オブジェクト `<binding>` の構造化：
   - `id`: グローバルに一意な整数 ID（`sym_1234` 等）。
   - `source-name`: デバッグ・エラー表示用の元のシンボル名。
   - `scope`: 所属するスコープノード（ファイル、関数、ブロック）。
   - `kind`: `'variable | 'function | 'typedef | 'tag | 'label`。
2. スコープ環境マネージャの実装：
   - スコープのプッシュ/ポップ、名前空間別の定義・検索プロトコル。
   - C 言語のいわゆる Lexer Hack（typedef 名か変数名かの動的判定）をサポートするクエリ API の提供。
3. Scheme コンパイラおよび将来のインタプリタでの共用：
   - クロージャ変換における自由変数抽出を Binding ID の集合演算として高速化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 深くネストしたブロックスコープで同名変数がシャドウイングされた場合でも、各変数が一意な Binding ID に正確に分解され、意図せぬ参照破壊が発生しないこと。
- [ ] C 言語の typedef 宣言と変数宣言の文脈依存な名前解決が正しく判定されること。
- [ ] 単体テスト `test_scope_and_binding.scm` がパスすること。

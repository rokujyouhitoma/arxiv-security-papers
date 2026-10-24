---
ID: 600
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] 統合シンボル・スコープ解決基盤および α 変換（Alpha-Conversion）エンジンの導入 (ID: 600)

## 1. 概要 / Summary
マクロ展開（Pass 020）、構文脱糖（Pass 030）、トップレベル巻き上げ（Pass 025）、クロージャ変換（Pass 110）などの各段階で発生する変数シャドウイングおよび名前衝突（未束縛変数例外や意図しない捕捉）を根絶するため、統合された **字句スコープ解決基盤と α 変換（Alpha-Conversion / 一意識別子化）エンジン** を導入する。

### 背景と課題:
1. **名前衝突バグの頻発**:
   - Issue #588（論理積 and 脱糖漏れによる未束縛例外）や Issue #592（内部定義脱糖未実装による未束縛例外）のように、パス間でのスコープ管理・名前バインディングの不整合によるバグが継続的に発生している。
2. **アドホックな一意シンボル生成**:
   - `unique-symbol` や `gensym` が各パスで局所的に使われているが、AST 全体での字句的スコープ構造（Lexical Scope Tree）や束縛・参照の一対一対応が形式的に保持されていない。
3. **後続パスの認知負荷**:
   - 最適化パス（CP0, インライン展開, LVN 等）が変数名のシャドウイングを常に警戒しながら再帰する必要があり、コードが複雑化している。

---

## 2. トレーサビリティ / Traceability
- 関連 Issue:
  - Issue #588: [論理積構文 (and) の脱糖漏れによる LIR 未束縛変数例外の解消](closed/588-fix-and-syntax-desugaring-unbound-variable-in-lir.md)
  - Issue #592: [手続き本体および内部定義の脱糖未実装による未束縛変数例外](closed/592-implement-r7rs-internal-definition-desugaring.md)
  - Issue #594: [Frontend層: define-language L_anf / L_lifted の導入と不変条件自動検証](594-define-frontend-anf-and-lifted-languages.md)
- 関連仕様書:
  - [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm) (新規: 字句スコープ解決 & α 変換エンジン)
- [ ] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm) (マクロ展開後の一意識別子正規化)
- [ ] [ulisp/frontend/025_top_level.scm](../../ulisp/frontend/025_top_level.scm) (トップレベル環境との境界定義)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm) (脱糖パスでのスコープ連携)
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm) (シンボル生成ユーティリティの整理)
- [ ] [ulisp/tests/test_scope.scm](../../ulisp/tests/test_scope.scm) (新規: シャドウイング・自由変数捕捉防止テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/600-implement-unified-lexical-scope-and-alpha-conversion-engine`

1. **Scope Tree & Binding Environment の形式化**:
   - 親スコープポインタ、宣言変数リスト、自由変数参照リストを持つ `scope-node` データ構造を定義。
   - レキシカルスコープのネスト関係を AST と並行してトラバース・構築するルーチンを整備。
2. **全自動 α 変換（Alpha-Conversion）パスの先行適用**:
   - 脱糖直後（Pass 030 の完了時）に全束縛変数に対し、一意なプレフィックス/サフィックス付き識別子（例: `x$123`）またはシンボルオブジェクトを割り当て。
   - これ以降の全パス（ANF, 最適化, クロージャ変換, LIR）において「変数はプログラム全体で一意」という強力な不変条件（Barendregt Convention）を確立。
3. **未束縛変数の早期検出**:
   - スコープ解決段階で、トップレベル未定義またはローカル未束縛な変数をコンパイル初期段階で確定的に検出し、分かりやすい診断メッセージを出力。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 脱糖後の AST に対し、シャドウイングされた同名変数が完全に一意なシンボルへ α 変換されること
- [ ] 未束縛変数が LIR 生成まで漏れずに、フロントエンドのスコープ解決段階で 100% 検出されること
- [ ] α 変換後もプログラムのセマンティクス（動作結果）が完全に維持されること
- [ ] 既存の全テストスイート（`make test`）が 100% PASS すること

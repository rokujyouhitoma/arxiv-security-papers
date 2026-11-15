---
ID: 837
種別: Feature
優先度: Medium
ステータス: Open (In Progress)
---

# [FEAT] 構文解析後の一意束縛解決 (Binding ID) とスコープ環境管理の共通基盤化 (ID: 837)

## 1. 概要 / Summary

フロントエンドの構文解析・脱糖直後（Early Phase / Pass 035）において、すべての変数・識別子を単なる「文字列/シンボル」から、一意な整数識別子と属性メタデータを備えた第一級の束縛オブジェクト（`<binding>` / `<binding-id>`）へと解決・登録する共通のレキシカルスコープ管理および α 変換（Alpha Conversion）基盤を構築する。

C99 言語の複数名前空間（`ordinary`: 通常変数・関数・`typedef` 名・`enum` 定数、`tag`: `struct`/`union`/`enum` タグ名、`label`: 関数スコープ `goto` ラベル）およびブロックスコープのシャドウイング規則と、Scheme（R7RS）のレキシカルスコープ・衛生的マクロ展開（Scope Sets: Binding as Sets of Scopes）を、単一の「レキシカルスコープ木（Contour Tree）＋ 多重名前空間束縛解決エンジン」として統合モデル化する。これにより、C パーサにおける Lexer Hack（`TYPEDEF_NAME` vs `IDENTIFIER` の文脈判定）を $O(1)$〜$O(\text{depth})$ で解決するとともに、後続の ANF 変換・型推論（S-RTyper）・クロージャ変換（Pass 110）・LIR Lowering において変数名衝突やシャドウイングの考慮を完全に不要化する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-33-02 (ULisp 多言語フロントエンド統合および機械型付き LIR 拡張設計書)](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md): §2.1 (Parser & Sema / Lexer Hack), §3.2 (統一束縛解決 Binding ID とレキシカルスコープ基盤)
  - [DSN-33 (ULisp Underlying x86 Native AOT Compiler Architecture)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md): Pass 0b (Hygienic Macro Expander) & Pass 035 (Lexical Scope & Alpha-Conversion)
  - [DSN-33-01 (ULisp Pipeline / Pass / Nanopass / Picopass DAG Architecture)](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md): フロントエンド正規化パイプライン
- **関連 Issue**:
  - [Issue #824 (Nanopass AST ノードにおけるソース位置情報 Source Span とメタデータの第一級サポート)](closed/824-support-first-class-source-span-and-ast-metadata-in-nanopass.md)
  - [Issue #825 (Nanopass AST 定数式評価器 eval-in-language およびコンパイル時計算 CTFE 基盤の導入)](closed/825-implement-eval-in-language-ast-evaluator-for-ctfe-and-constant-folding.md)
  - [Issue #833 (コンパイラ・マクロ展開・インタプリタ共通の統合エラー診断エンジン Diagnostic Reporter の導入)](closed/833-implement-unified-pretty-diagnostic-reporter-for-compiler-and-runtime.md)
  - [Issue #835 (Core Machine LIR と Managed Runtime Dialect の完全直交分離)](closed/835-separate-core-machine-lir-from-managed-runtime-dialect.md)
  - [Issue #836 (`define-value-repr` による値表現・ボクシング方式のプラグイン化)](closed/836-plugin-value-representation-and-boxing-scheme.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/compiler/binding.scm](../../ulisp/compiler/binding.scm): `<binding>` レコード定義（`id`, `source-name`, `unique-sym`, `kind`, `namespace`, `scope-id`, `storage-class`, `type-attr`, `visibility`, `scope-set`, `source-span`）、グローバル束縛レジストリ（`*binding-registry*`）、Binding ID 順序集合演算（`binding-id-set-*`）、および衛生的マクロ用 Scope Sets（`scope-set-*`, `resolve-hygienic-binding`）の実装
- [ ] [ulisp/compiler/scope.scm](../../ulisp/compiler/scope.scm): レキシカルスコープ木の多重名前空間（`'ordinary`, `'tag`, `'label`, `'macro`）拡張、スコープ環境マネージャ（`make-scope-manager`, `scope-manager-push!`, `scope-manager-pop!`）、C99 Lexer Hack クエリ API（`scope-lookup-kind`, `scope-typedef-name?`）、同一スコープ不正再定義検知、および Pass 035 α 変換エンジンと `<binding>` レジストリの統合
- [ ] [ulisp/frontend/040_analysis.scm](../../ulisp/frontend/040_analysis.scm): 自由変数解析と Binding ID 集合演算（`free-binding-ids`, `scope-extract-free-binding-ids`）の連携インターフェース追加
- [ ] [ulisp/compiler/module_header.scm](../../ulisp/compiler/module_header.scm): モジュール分割コンパイル用 `%declare-extern-identifiers` への `binding.scm` / `scope.scm` 新規公開シンボルの登録
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm): AOT コンパイル用シンボル文字列変換テーブルへの新規識別子登録（必要な場合）
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `COMPILER_BASE` への `compiler/binding.scm` 追加および `test_scope_and_binding` テストターゲットの登録
- [ ] [ulisp/tests/test_scope_and_binding.scm](../../ulisp/tests/test_scope_and_binding.scm): `<binding>` レコード、多重名前空間、C99 Lexer Hack（`typedef` とブロック変数の相互シャドウイング）、Scope Sets 衛生性解決、多重ブロックスコープ α 変換、および Binding ID 集合による自由変数計算を網羅する単体テストスイート

---

## 4. 脅威モデルとセキュリティ・堅牢性要件 / Threat Model & Security Requirements

1. **THREAT-837-1: シャドウイング解決ミスによる変数参照すり替え（Variable Capture / Shadowing Confusion）**
   - **リスク**: ネストしたブロックスコープやマクロ展開において、内側の同名束縛（あるいは `let` の RHS 評価時点での外側束縛）が誤ったスコープ階層へ解決されると、権限検査変数やポインタ変数が別オブジェクトを参照する深刻な論理バグ・メモリ破壊を引き起こす。
   - **対策**:
     - `let` では RHS 式を必ず親スコープで α 変換した後に子スコープへ束縛を追加し、`letrec` では子スコープに全束縛を先行登録してから RHS を変換する不変条件を維持する。
     - すべての束縛に単調増加する一意な `<binding-id>` と `unique-sym`（`name$id`）を割り当て、`*binding-registry*` で双方向追跡可能にする。
2. **THREAT-837-2: C99 名前空間混同および Lexer Hack 誤判定（Namespace & Typedef Disambiguation Hazard）**
   - **リスク**: C99 では `struct foo`（`tag` 名前空間）、`typedef int foo;`（`ordinary` 名前空間）、`foo:`（関数単位の `label` 名前空間）が独立して共存する。さらに内側のブロックで `int foo = 1;` が宣言されると、そのブロック内では `foo` は `TYPEDEF_NAME` ではなく通常の `IDENTIFIER`（変数）へと動的に切り替わる。名前空間の混同やシャドウイング判定漏れは構文解析の破綻や型誤認を招く。
   - **対策**:
     - スコープノードに名前空間別の束縛テーブルを設け、`scope-lookup-binding` が `namespace` 引数（`'ordinary`, `'tag`, `'label`, `'macro`）に従って厳密に分離検索を行う。
     - `'label` 名前空間の定義・検索は、現在のブロックスコープから最も近い関数スコープ（`'function` または `'lambda`、存在しない場合はルート）へ正規化する。
     - `(scope-typedef-name? scope sym)` は `'ordinary` 名前空間を内側から外側へ探索し、最初に見つかった `<binding>` の `binding-kind` が `'typedef` の場合のみ `#t` を返し、内側で `'variable` や `'parameter` によりシャドウイングされていれば `#f` を返す。
3. **THREAT-837-3: スコープスタックのアンダーフローおよび同一スコープ内の不正再定義（Scope Stack Underflow & Illegal Redefinition）**
   - **リスク**: 構文エラー回復時や不正な AST 走査時にルートスコープを超えて `pop` するとスコープ環境が `#f` に破壊される。また、同一ブロックスコープ・同一名前空間内で異なる種別の識別子（例: `typedef int x; int x;`）が重複定義された際に無警告で上書きすると意味解析の不整合が生じる。
   - **対策**:
     - `scope-manager-pop!` で親スコープが `#f`（ルート）の場合は `(raise (list 'scope-error ...))` を送出し、環境破壊を防止する。
     - `scope-define-binding!` に `allow-shadow-in-same-scope?` オプション（または厳格モード判定）を備え、同一スコープ・同一名前空間内の不正再定義を確定的に検出して構造化例外を送出可能にする。
4. **THREAT-837-4: 衛生的マクロ Scope Sets における曖昧束縛（Ambiguous Hygienic Binding Resolution）**
   - **リスク**: 複数のマクロ展開スコープマークが交差する識別子解決において、部分集合関係にない複数の極大候補が存在する場合に任意の候補を選択すると衛生性（Hygiene）が破れる。
   - **対策**: Flatt (2016) の "Binding as Sets of Scopes" アルゴリズムに従い、候補束縛の `scope-set` のうち参照側 `use-scope-set` の部分集合となるものを抽出し、最大要素数を持つ候補が他のすべての候補のスーパーセットであることを検証する（比較不能な極大候補が存在する場合は `'hygiene-ambiguity-error` を送出する）。

---

## 5. 詳細設計と実装方針 / Detailed Design & Implementation Plan

Target Branch: `feat/837-unified-symbol-binding-resolution`

### Step 1: `ulisp/compiler/binding.scm` の新規実装

1. **エラー送出ヘルパ**:
   - `(binding-error! msg detail)` -> `(raise (list 'binding-error msg detail))`（`guard` で捕捉可能な構造化例外）。
2. **`<binding>` オブジェクト表現とアクセサ**:
   - タグ付きリストまたはベクタ構造 `(list 'binding id source-name unique-sym kind namespace scope-id storage-class type-cell visibility-cell scope-set span-cell)`:
     - `(make-binding id source-name unique-sym kind namespace scope-id storage-class type-attr visibility scope-set source-span)`
     - `(binding? obj)`
     - `(binding-id b)`: 非負整数 ID (`0, 1, 2, ...`)
     - `(binding-source-name b)`: 元のシンボル (`'x`)
     - `(binding-unique-sym b)`: α 変換後の一意シンボル (`'x$0`、トップレベル等の非リネーム束縛では元のシンボル)
     - `(binding-kind b)`: `'variable | 'parameter | 'function | 'typedef | 'tag-struct | 'tag-union | 'tag-enum | 'enum-const | 'label | 'macro | 'builtin`
     - `(binding-namespace b)`: `'ordinary | 'tag | 'label | 'macro`
     - `(binding-scope-id b)`: 所属スコープノードの整数 ID
     - `(binding-storage-class b)` / `(set-binding-storage-class! b sc)`: `'auto | 'register | 'static | 'extern | 'typedef | 'lexical | 'global`
     - `(binding-type-attr b)` / `(set-binding-type-attr! b ty)`: 型アノテーション（初期値 `#f`）
     - `(binding-visibility b)` / `(set-binding-visibility! b vis)`: `'local | 'file | 'global | 'hidden`
     - `(binding-scope-set b)` / `(set-binding-scope-set! b sset)`: 衛生スコープマークの昇順整列リスト
     - `(binding-source-span b)` / `(set-binding-source-span! b span)`: `<source-span>` または `#f`
3. **グローバル束縛レジストリ (`*binding-registry*`)**:
   - `reset-binding-registry!`: レジストリを初期化する（`reset-alpha-symbol-counter!` からも連動呼び出しする）。
   - `(register-binding! b)`: `id` および `unique-sym` をキーとして登録し、`b` を返す。
   - `(lookup-binding-by-id id)` / `(lookup-binding-by-symbol sym)`: 登録済み `<binding>` を返す（未登録時は `#f`）。
   - `(all-registered-bindings)`: 登録順に `<binding>` リストを返す。
4. **Binding ID 順序集合演算 (`binding-id-set`)**:
   - 整数 ID の重複なし昇順リストとして表現し、高速な集合演算を提供する：
     - `binding-id-set-empty` (`'()`)
     - `(binding-id-set-member? id bset)`
     - `(binding-id-set-add id bset)`
     - `(binding-id-set-union bset1 bset2)`
     - `(binding-id-set-difference bset1 bset2)`
     - `(binding-id-set-intersection bset1 bset2)`
     - `(binding-id-set-equal? bset1 bset2)`
     - `(symbols->binding-id-set syms)`: シンボル列から解決可能な `<binding-id>` を抽出し整列集合化する。
     - `(binding-id-set->symbols bset)`: `<binding-id>` 集合から対応する `binding-unique-sym` のリストへ変換する。
5. **衛生的マクロ Scope Sets ("Binding as Sets of Scopes")**:
   - `*hygiene-scope-counter*`, `(reset-hygiene-scope-counter!)`, `(fresh-hygiene-scope!)`
   - `scope-set-empty`, `(scope-set-member? mark sset)`, `(scope-set-add mark sset)`, `(scope-set-remove mark sset)`, `(scope-set-flip mark sset)`
   - `(scope-set-subset? sset1 sset2)`, `(scope-set-equal? sset1 sset2)`, `(scope-set-size sset)`
   - `(resolve-hygienic-binding candidate-bindings use-scope-set)`:
     - `candidate-bindings` の中から `(scope-set-subset? (binding-scope-set b) use-scope-set)` を満たす候補を抽出。
     - 候補が空なら `#f`。
     - 最大サイズの `scope-set` を持つ候補 `best` を選び、他のすべての有効候補 `c` について `(scope-set-subset? (binding-scope-set c) (binding-scope-set best))` が成り立つことを検証。成り立たない場合は `(binding-error! "Ambiguous hygienic binding resolution" ...)` を送出する。

### Step 2: `ulisp/compiler/scope.scm` の多重名前空間・Lexer Hack・`<binding>` 統合

1. **既存 API の完全後方互換維持**:
   - `scope-node` の先頭 6 要素 `('scope-node parent kind bindings-cell free-vars-cell children-cell ...)` を維持し、第 7 要素として `scope-id`、第 8 要素として `ns-bindings-cell`（名前空間別 `<binding>` リスト）を保持する。
   - `scope-node-id` アクセサおよび `*scope-id-counter*` / `reset-scope-id-counter!` を追加する。
2. **多重名前空間と C99 Lexer Hack API**:
   - `(scope-find-function-contour node)`: `'label` 名前空間用に、現在のノードから親方向へ探索し `'function` または `'lambda`（なければ最上位のルートノード）を返す。
   - `(scope-define! node source-name kind . opts)`:
     - `opts` からオプションの `namespace`（省略時は `kind` から自動推論: `'tag-struct | 'tag-union | 'tag-enum` $\to$ `'tag`、`'label` $\to$ `'label`、`'macro` $\to$ `'macro`、その他 $\to$ `'ordinary`）、`storage-class`、`type-attr`、`visibility`、`scope-set`、`source-span`、`unique-sym`、`strict-redef?` を受け取る。
     - `strict-redef?` が `#t` の場合、対象スコープ（`'label` の場合は関数スコープ）の同一名前空間内に同名の `<binding>`（かつ同一 `scope-set`）が既に存在すれば `(raise (list 'scope-error "Redefinition of symbol in same scope" source-name))` を送出する。
     - 新規 `<binding>` を生成・登録し、`'ordinary` 名前空間の場合は既存の `bindings-cell` (`(orig-sym . unique-sym)`) にも同期登録して `<binding>` を返す。
   - `(scope-lookup-binding-local node sym . ns-opt)` / `(scope-lookup-binding node sym . ns-opt)`:
     - 指定名前空間（デフォルト `'ordinary`）で `<binding>` を探索する（`'label` の場合は関数スコープを検索）。
   - `(scope-lookup-hygienic node sym use-scope-set . ns-opt)`:
     - 内側から外側までの全可視スコープから `sym` の候補 `<binding>` を収集し、`resolve-hygienic-binding` で最適束縛を解決する。
   - **C99 Lexer Hack クエリ**:
     - `(scope-lookup-kind node sym)`: `'ordinary` 名前空間で `sym` を検索し、見つかった `<binding>` の `binding-kind`（未定義なら `#f`）を返す。
     - `(scope-typedef-name? node sym)`: `(eq? (scope-lookup-kind node sym) 'typedef)` を返す。
3. **スコープ環境マネージャ (`scope-manager`)**:
   - `(make-scope-manager)` / `(scope-manager? obj)`
   - `(scope-manager-root mgr)` / `(scope-manager-current mgr)`
   - `(scope-manager-push! mgr kind)`: 新しい子スコープへ入り、`current` を更新して返す。
   - `(scope-manager-pop! mgr)`: 親スコープへ戻る（ルートスコープでの pop は `(raise (list 'scope-error ...))` を送出）。
   - `(scope-manager-define! mgr sym kind . opts)` / `(scope-manager-lookup mgr sym . ns-opt)` / `(scope-manager-typedef-name? mgr sym)`。
4. **Pass 035 (`scope-resolve-all` / `alpha-convert-expr`) との統合**:
   - `reset-alpha-symbol-counter!` 実行時に `reset-binding-registry!` と `reset-scope-id-counter!` もリセットする。
   - `scope-bind!` が呼ばれた際、対応する `<binding>` オブジェクトを生成して `ns-bindings-cell`（`'ordinary`）および `*binding-registry*` に自動登録する。
   - `alpha-convert-expr` が AST ノードの `<source-span>`（`ast-has-span?` / `ast-source-span`）を持つ場合、変換後のノードに Span を保持しつつ生成される `<binding>` にも `source-span` を記録する。
   - `scope-last-root-node`（直近の `alpha-convert-program` で構築されたルート `scope-node` を取得する検査用アクセサ `(get-last-resolved-scope-tree)`）を提供する。

### Step 3: `ulisp/frontend/040_analysis.scm` への Binding ID 自由変数抽出連携

- `(free-binding-ids expr bound-syms)`: `free-vars` で抽出した自由変数シンボル集合を `symbols->binding-id-set` により正規化された `<binding-id>` 順序集合へ変換して返すヘルパ関数を追加する。
- `(closure-capture-binding-ids lambda-expr bound-syms)`: ラムダ式がキャプチャすべき外部レキシカル束縛（`*binding-registry*` に登録されたローカル/パラメータ束縛のみ、プリミティブやトップレベル関数を除外）の `<binding-id>` 集合を返すヘルパを追加する。

### Step 4: ビルド設定・外部識別子登録・単体テスト

- `ulisp/compiler/module_header.scm` および `ulisp/compiler/helpers.scm` に公開シンボルを追加する。
- `ulisp/Makefile` の `COMPILER_BASE`（`compiler/scope.scm` の直前）に `compiler/binding.scm` を追加し、`test_scope_and_binding` ターゲットを登録する。
- `ulisp/tests/test_scope_and_binding.scm` を作成し、以下の 5 グループを検証する：
  - **Group 1**: `<binding>` レコード生成、属性ミューテータ、`*binding-registry*` 双方向検索、および `binding-id-set` 集合演算（union / intersection / difference / canonical ordering）。
  - **Group 2**: C99 多重名前空間（`'ordinary`, `'tag`, `'label`）の独立性と関数スコープ `'label` 解決、同一スコープ不正再定義のエラー検出。
  - **Group 3**: C99 Lexer Hack（`scope-typedef-name?` / `scope-lookup-kind`）と多重ブロックスコープでの `typedef` $\leftrightarrow$ 変数シャドウイングおよび `scope-manager-push!` / `scope-manager-pop!` 状態遷移（アンダーフロー防御含む）。
  - **Group 4**: Scheme 衛生的マクロ Scope Sets（`scope-set-flip`, `scope-set-subset?`, `resolve-hygienic-binding`, 曖昧束縛エラー検出）。
  - **Group 5**: Pass 035 α 変換における `<binding>` 自動登録、Source Span 伝播、深層ネストブロックスコープのシャドウイング安全性、および `free-binding-ids` / `closure-capture-binding-ids` との統合検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] `ulisp/compiler/binding.scm` が実装され、`<binding>` レコード、`*binding-registry*`、`binding-id-set` 集合演算、および Scope Sets（`resolve-hygienic-binding`）が動作すること。
- [ ] `ulisp/compiler/scope.scm` が多重名前空間（`'ordinary`, `'tag`, `'label`, `'macro`）、`scope-manager`、および C99 Lexer Hack クエリ（`scope-lookup-kind`, `scope-typedef-name?`）を備え、Pass 035 α 変換時にすべての束縛を `<binding>` として登録すること。
- [ ] 深くネストしたブロックスコープで同名変数や `typedef` 名がシャドウイングされた場合でも、各束縛が一意な `<binding-id>` と `unique-sym` に分解され、スコープ退出（pop）時に外側の可視性が正確に復元されること。
- [ ] 新規単体テストスイート `ulisp/tests/test_scope_and_binding.scm`（`make -C ulisp test_scope_and_binding`）および既存 `make -C ulisp test_scope` が 100% PASS すること。
- [ ] 既存の全テストスイート（`test_pass_manager`, `test_passes`, `test_nanopass_source_span` 等）および `make py_compile && make static_analysis` に一切の回帰がないこと。

---
ID: 824
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] Nanopass AST ノードにおけるソース位置情報 (Source Span) とメタデータの第一級サポート (ID: 824)

## 1. 概要 / Summary
Nanopass フレームワーク（`define-language` / `define-pass` / `define-picopass`）の AST 構築・走査・変換基盤を拡張し、元のソースコード位置情報（ファイルパス、開始行/列、終了行/列、マクロ展開元、ノードID）を各 AST ノードに第一級メタデータとして不可分に付与・透過的に伝播させる `<source-span>` 機構を導入する。

現行の uLisp では、最上位フォーム単位での大まかな位置情報（`%source-loc`）をコンテキスト大域変数に記録しているのみであり、脱糖（Desugaring）、CPS/ANF 変換、マクロ展開、および LIR への Lowering を通過する過程で部分式のソース位置が脱落していた。
本改修により、中間言語（$L_{\text{cst}} \to L_{\text{src}} \to L_{\text{core}} \to L_{\text{anf}} \to L_{\text{lifted}} \to \text{LIR}$）の全走査パスを通じて正確なソース位置およびマクロ展開元（Macro Origin）を不変条件として保持し、Clang / Rustc スタイルの美麗な診断報告（Issue #833）、DWARF デバッグシンボルの精密生成、および今後実装される C 言語フロントエンド（Issue #826, #837）における正確な構文・意味エラー診断の基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §1 (フロントエンド診断基盤とコンパイラ内部基盤), §2 (B5: 型付き C の IR 言語定義)
- **DSN-33-01**: §4 (Pass 1 Frontend Phase / `femto: attach-source-span`), §7 (Pass Manager 統合)
- **DSN-33-02**: §3.1 (第一級ソース位置情報 (Source Span) と来歴追跡 (Issue #824)), §3.4 (統合 Pretty Diagnostic Reporter (Issue #833))
- **関連 Issue**:
  - #606: R7RS include and Source Location Tracking
  - #756: Picopass/Femtopass DSL & DAG Optimization Pipeline
  - #815: Nanopass Catamorphism & Pattern Match Optimization
  - #825: Nanopass AST 定数式評価器 (eval-in-language) および CTFE 基盤
  - #826: 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行
  - #833: 統合 Pretty Diagnostic Reporter
  - #837: 統一識別子スコープと Binding ID 解決基盤

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/compiler/helpers.scm](../../ulisp/compiler/helpers.scm):
  - 新設：`<source-span>` 不変レコード定義、不変空スパン定数、境界検証付きファクトリ `make-source-span`、および AST ノードアノテーション API群（`ast-source-span`, `ast-with-span`, `ast-strip-span`, `ast-has-span?`）
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm) & [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm):
  - Nanopass パターンマッチャおよびテンプレート展開部における透過的 Span 伝播フック（親ノードの Span を出力ノードへ暗黙継承）
- [ ] [ulisp/frontend/010_library.scm](../../ulisp/frontend/010_library.scm):
  - ファイルインクルード・読み込み時のトークンレベル Span 生成と初期 AST への付与
- [ ] [ulisp/frontend/020_macro_expander.scm](../../ulisp/frontend/020_macro_expander.scm):
  - 衛生的マクロ展開時の `macro-origin`（展開元 Span）チェーンの記録と合成
- [ ] [ulisp/frontend/025_top_level.scm](../../ulisp/frontend/025_top_level.scm) 〜 [ulisp/frontend/120_alias_escape.scm](../../ulisp/frontend/120_alias_escape.scm):
  - 各 Frontend 変換パスにおける Span 保持確認と脱糖時（`let`, `cond`, `case`, `do` 等）の子ノード Span 継承
- [ ] [ulisp/tests/test_nanopass_source_span.scm](../../ulisp/tests/test_nanopass_source_span.scm):
  - 新設：Nanopass 全パス通過時の Span 保持、マクロ展開来歴追跡、境界値検証、およびオーバーヘッド測定テスト
- [ ] [ulisp/Makefile](../../ulisp/Makefile) & [Makefile](../../Makefile):
  - `make test_nanopass_source_span` ターゲットの追加と CI/品質ゲートへの統合

---

## 4. 脅威モデルとセキュリティ検証 (Threat Model & Security Mitigation)

| 脅威項目 (Threat Vector) | 影響度 | 脆弱性メカニズム | 対策・緩和策 (Mitigation) |
| :--- | :---: | :--- | :--- |
| **CWE-119 / CWE-125: 境界外読込によるクラッシュ・不正表示** | Medium | 不正な開始/終了行番号・列番号（負数、`end < start`、0オリジン混入）により、診断レポータがソース行キャッシュ配列の境界外を参照する。 | `make-source-span` において厳格な不変条件アサーション（`1 <= start-line <= end-line` かつ `1 <= start-col`）を強制。不正な値はサニタイズまたは安全なフォールバックを適用。 |
| **CWE-400: メタデータ肥大化によるヒープ枯渇** | High | すべての微小な式ノードに重厚なレコードを個別割り当てすることで、AST のメモリフットプリントが急増し OOM を引き起こす。 | 合成ノード（Synthetic Nodes）向けにシングルトン空スパン `*no-source-span*` を再利用（Flyweight パターン）。7要素の最適化スパン表現を用い、メモリ増加率を 5% 未満に抑制。 |
| **CWE-843: メタデータハンドルの型混乱** | Medium | 通常のリストやタグ付きタプルと `<source-span>` が混同され、パーサや変換パスが誤動作する。 | 独立したレコード型 `<source-span>`（型述語 `source-span?`）を採用。S式パターンマッチを阻害しない透過的アノテーションラッパーを導入。 |
| **CWE-22: ソースファイルパスのディレクトリトラバーサル** | Low | include されたソースパスに `../` や絶対パスが含まれ、エラーログ等を通じてホストの内部ディレクトリ構造が漏洩する。 | `sanitize-source-path` による相対パス正規化を適用し、安全なリポジトリ相対パスのみを Span 内に保持。 |

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/824-nanopass-source-span-metadata`

### 5.1 `<source-span>` 不変データ構造と API 仕様 (`ulisp/compiler/helpers.scm`)
DSN-33-02 §3.1 に完全準拠したレコード型を定義する。
```scheme
(define-record-type <source-span>
  (%make-source-span-raw file start-line start-col end-line end-col macro-origin node-id)
  source-span?
  (file         span-file)
  (start-line   span-start-line)
  (start-col    span-start-col)
  (end-line     span-end-line)
  (end-col      span-end-col)
  (macro-origin span-macro-origin)
  (node-id      span-node-id))
```
- **ファクトリ関数**:
  `(make-source-span file s-line s-col e-line e-col [macro-origin] [node-id])`
  - 入力アラインメント検査: `s-line >= 1`, `s-col >= 1`, `e-line >= s-line`
  - `node-id` の自動採番（不可分インクリメント）
  - 定数 `*no-source-span*`: 不明・コンパイラ生成ノード用シングルトン
- **AST アノテーション API**:
  - `(ast-with-span form span)` $\to$ 位置情報を付与した AST 表現を生成
  - `(ast-source-span form)` $\to$ ノードの位置情報を取得（付与されていない場合は `#f` または親/コンテキスト Span）
  - `(ast-strip-span form)` $\to$ メタデータを剥がした純粋な構文 S 式を取得
  - `(ast-has-span? form)` $\to$ ブール値判定

### 5.2 Nanopass エンジンにおける透過的伝播機構 (`ulisp/compiler/nanopass.scm`)
1. **コンテキスト Span トラッキング**:
   - パス走査中、入力式ノードを再帰走査するたびに動的パラメータ `*current-input-span*` を更新。
2. **自動継承フック (Transparent Inheritance)**:
   - `define-pass` 出力生成子において、変換先の新しいノードが Span を持たない場合、`*current-input-span*` から自動的に Span を継承させる。
   - `define-picopass` 最適化ルール（例: 定数畳み込み `(+ 1 2) -> 3`）において、畳み込み後の結果値ノードに元の加算式の Span をそのまま付与。

### 5.3 Reader / Include / Macro Expander 連携
1. **010_library.scm**:
   - `read-datum-or-source-loc` を拡張し、従来の `%source-loc` に加え、トークン終了位置を捕捉して `<source-span>` を生成。
2. **020_macro_expander.scm**:
   - マクロ展開時に、展開前ノードの Span を `macro-origin` として展開後コード内の全ノードにチェーン付与。
   - 複数段マクロ（マクロが別のマクロを展開）における深層トレースを可能化。

### 5.4 Frontend パイプライン通過検証 (`025` 〜 `120`)
- `025_top_level`: 最上位定義（関数名、引数、本体）の Span 保存
- `026_desugar_constructors` 〜 `029_desugar_dynamic`: 脱糖された `if`, `let` 構造が元の構文の Span を正しく分割・継承することの保証
- `070_anf` 〜 `080_annotator`: 原子被演算子（Atomic Operands）の型アノテーション時にも元の Span を不可分に維持

### 5.5 単体・統合テストスイート構築 (`ulisp/tests/test_nanopass_source_span.scm`)
- **Group 1**: `<source-span>` 基本操作、バリデーション、シングルトン空スパン
- **Group 2**: AST アノテーション付与・抽出・ストリップの等価性検証
- **Group 3**: Nanopass パス通過時（$L_{\text{cst}} \to L_{\text{core}} \to L_{\text{anf}} \to \text{LIR}$）の Span 透過伝播
- **Group 4**: マクロ展開元の階層追跡（`macro-origin` チェーン）
- **Group 5**: CWE-119 / CWE-400 / CWE-843 セキュリティ境界ガード
- **Group 6**: メモリおよびコンパイル時間のオーバーヘッド測定（< 5% 検証）

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] **`<source-span>` レコードおよびコア API 実装**:
  - `ulisp/compiler/helpers.scm` に DSN-33-02 §3.1 準拠の `<source-span>`、`make-source-span`、`ast-with-span`、`ast-source-span`、`ast-strip-span` が実装されていること。
- [x] **Nanopass 透過伝播の実現**:
  - `define-pass` および `define-picopass` の変換ルール適用時に親ノードの位置情報が脱落せず自動継承されること。
- [x] **マクロ展開来歴追跡 (`macro-origin`)**:
  - マクロ展開された AST ノードが元のマクロ呼び出し箇所の Span を `macro-origin` として保持していること。
- [x] **全 Frontend パイプラインでの非脱落性**:
  - パス 020 から 120 を経て LIR 生成に至るまで、終端ノードのソース位置情報が正しく保持されていること。
- [x] **オーバーヘッド基準適合**:
  - メタデータ付加によるコンパイル時間およびメモリ消費増加が 5% 未満であること。
- [x] **単体・回帰テスト 100% PASS**:
  - `make test_nanopass_source_span` が新設され、全テストケースが無エラーで通過すること。
  - 既存の全テストスイート（`make test`）にリグレッションが発生しないこと。
- [x] **相対パス完全準拠**:
  - 本ファイルおよび関連ドキュメントにおいて絶対パスリンクが 0 件であること。

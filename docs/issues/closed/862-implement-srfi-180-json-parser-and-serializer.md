---
ID: 862
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] SRFI 180 RFC 8259 準拠 JSON パーサおよびジェネレータ ((scheme json)) の実装 (ID: 862)

## 1. 概要 / Summary
R7RS-large Orange / Hypnos Docket においてデータ交換および入出力の標準として定められている **SRFI 180 (JSON)** は、RFC 8259 規格に完全準拠した JSON データのストリーミングおよびインメモリ双方向パーサ・シリアライザを規定する。
現代の Web API、CTI 脅威インテリジェンス、外部エコシステムとのデータ交換において JSON は事実上の世界共通標準フォーマットであり、コンパイラおよびツールチェーンの外部連携能力・自己完結性を飛躍的に高める。

現行の ULisp においては未実装（`×`）となっており、JSON データの読み書きがネイティブに利用できない状態にある。
本 Issue では、純粋 Scheme による完全自律型 RFC 8259 準拠 JSON パーサ・ジェネレータエンジンを [ulisp/lib/json.scm](../../ulisp/lib/json.scm) に実装し、R7RS-large 標準モジュール `(scheme json)` および `(srfi 180)` として提供する。

---

## 2. トレーサビリティ / Traceability
- **関連標準仕様**:
  - R7RS-large Orange / Hypnos Docket: `(scheme json)`
  - SRFI 180: [JSON](https://srfi.schemers.org/srfi-180/srfi-180.html) (by Amirouche Boubekki)
  - RFC 8259: The JavaScript Object Notation (JSON) Data Interchange Format
  - RFC 7464: JavaScript Object Notation (JSON) Text Sequences
  - [ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) §2.4 (Orange / Hypnos Docket 準拠状況)
  - [DSN-33 (ULisp 包括設計仕様書)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/json.scm](../../ulisp/lib/json.scm) (新規作成: RFC 8259 パーサ、字句解析器、シリアライザ、ストリーミングジェネレータ・アキュムレータ)
- [x] [ulisp/lib/srfi/180.sld](../../ulisp/lib/srfi/180.sld) (新規作成: `(srfi 180)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/lib/scheme/json.sld](../../ulisp/lib/scheme/json.sld) (新規作成: `(scheme json)` ライブラリ定義、Traceability ヘッダー)
- [x] [ulisp/tests/test_srfi_180.scm](../../ulisp/tests/test_srfi_180.scm) (新規作成: RFC 8259 公式準拠テスト・エッジケース・セキュリティ境界テストスイート)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`test_srfi_180` ターゲット追加、`lint_sexpr`、`test:` への登録)
- [x] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md) (SRFI 180 準拠ステータスを `◎` に更新)
- [x] [docs/issues/README.md](README.md) (Issue 台帳更新: ステータス管理)

---

## 4. 仕様定義とアーキテクチャ設計 / Specification & Architecture Design

### 4.1 エクスポート識別子一覧 (SRFI 180 公式全 12 識別子 + 拡張ユーティリティ)
SRFI 180 仕様に基づき、以下の述語、パラメータ、パーサ、プリンタをエクスポートする：

1. **エラー & 述語 (Predicates & Errors)**:
   - `json-error?`: オブジェクトが JSON 構文エラー、制限超過、または型違反によって送出されたエラーかを判定する述語（`read-error?` および `error-object?` を満たす）。
   - `json-error-reason`: `json-error` オブジェクトから人間可読なエラー理由文字列を取り出す手続き。
   - `json-null?`: オブジェクトが JSON の `null` 値（シンボル `'null`）であるかを判定する述語。
2. **パラメータ (Parameters)**:
   - `json-nesting-depth-limit`: JSON パース時および走査時の最大許容ネスト階層数を保持するパラメータ（デフォルト: `1000`）。
   - `json-number-of-character-limit`: パース対象 JSON テキストの最大文字数を保持するパラメータ（デフォルト: `#f`、無制限）。
3. **読み込み・パーサ (Readers & Parsers)**:
   - `json-read`: 入力ポートまたは文字ジェネレータから単一の JSON 値を読み込み、Scheme オブジェクトに変換して返却。
   - `json-generator`: 入力ポートまたは文字ジェネレータを受け取り、JSON 構造イベント（`'array-start`, `'object-start`, `'array-end`, `'object-end`, スカラー値）を順次 yield するジェネレータを返却。
   - `json-fold`: JSON 要素を再帰走査・畳み込み処理する高水準イテレータ手続き。
   - `json-lines-read`: 改行区切り JSON (JSON Lines / `ndjson`) を順次パースするジェネレータを返却。
   - `json-sequence-read`: RFC 7464 JSON Text Sequence（Record Separator 区切り）を順次パースするジェネレータを返却。
4. **書き出し・シリアライザ (Writers & Printers)**:
   - `json-write`: Scheme オブジェクトを受け取り、妥当な JSON テキストへシリアライズして出力ポートまたは文字アキュムレータへ出力。
   - `json-accumulator`: 出力ポートまたは文字アキュムレータを受け取り、構造イベントまたは Scheme 値を受け取って JSON テキストを出力するアキュムレータ手続きを返却。
5. **高水準変換ユーティリティ (Convenience Converters)**:
   - `string->json`: 文字列から JSON データをパース。
   - `json->string`: Scheme オブジェクトを JSON 文字列へ変換。
   - `bytes->json`: UTF-8 バイトベクタから JSON データをパース。
   - `json->bytes`: Scheme オブジェクトを UTF-8 バイトベクタへシリアライズ。

---

### 4.2 JSON ⇔ Scheme データ型マッピング規約
SRFI 180 仕様に厳格に従い、以下の双方向マッピングを確立する：

| JSON データ型 | Scheme データ型 | シリアライズ (`json-write`) 許容型 | 備考 |
| :--- | :--- | :--- | :--- |
| `null` | シンボル `'null` | `'null` (および `(void)` / `'()`) | `(json-null? 'null) => #t` |
| `true` | 真偽値 `#t` | `#t` | 厳格ブール値 |
| `false` | 真偽値 `#f` | `#f` | 厳格ブール値 |
| `number` | 数値 (Integer, Flonum, Bignum, Ratnum) | すべての Scheme 実数 | ULisp 数値塔と完全協調。指数表記 `1e10`、多倍長整数も完全保持 |
| `string` | 文字列 (`string`) | 文字列 (`string`) | UTF-8 エンコード、RFC 8259 エスケープ遵守 |
| `array` | ベクタ (`vector`) | ベクタ (`#(...)`) および リスト (`(...)`) | デフォルト読み出しは `vector` |
| `object` | シンボルキーの連想リスト (`alist`) | `((symbol . value) ...)` または `((string . value) ...)` | キーはシンボルとしてパース |

---

### 4.3 レキサー＆パーサー状態機械とストリーミングアーキテクチャ
1. **字句解析器 (Lexer / Tokenizer)**:
   - 入力源（テキストポート、バイトベクタ、ジェネレータ）から文字単位で走査。
   - 空白文字（`#\space`, `#\tab`, `#\newline`, `#\return`）をスキップ。
   - トークン種別:
     - `LBRACKET` (`[`), `RBRACKET` (`]`), `LBRACE` (`{`), `RBRACE` (`}`), `COLON` (`:`), `COMMA` (`,`)
     - `STRING` (二重引用符で囲まれ、`\n`, `\t`, `\r`, `\"`, `\\`, `\/`, `\uXXXX` を復元)
     - `NUMBER` (正規表現 `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?` に合致)
     - `TRUE` (`true`), `FALSE` (`false`), `NULL` (`null`)
     - `EOF`
2. **Unicode サロゲートペア処理**:
   - `\uXXXX` 形式の 16進 4桁をパース。
   - 上位サロゲート（`0xD800`〜`0xDBFF`）を検出した場合、直後に続く `\uXXXX` が下位サロゲート（`0xDC00`〜`0xDFFF`）であることを厳格検査。
   - 有効なサロゲートペアはコードポイント `0x10000 + ((high - 0xD800) * 0x400) + (low - 0xDC00)` にデコードして UTF-8 文字へ変換。
   - 単独のサロゲート（孤立した上位サロゲートや下位サロゲート）は RFC 8259 に基づき `json-error` を送出。
3. **ストリーミングイベントプロトコル (`json-generator`)**:
   - 巨大な JSON ファイル全体をメモリにロードすることなく、1 トークン／1 構造イベントごとに消費可能。
   - yield されるイベント:
     - `'array-start` : 配列の開始
     - `'array-end` : 配列の終了
     - `'object-start` : オブジェクトの開始
     - `'object-end` : オブジェクトの終了
     - スカラー値 (`'null`, `#t`, `#f`, 数値, 文字列)
     - オブジェクト内部ではキー（文字列またはシンボル）と値が交互に出現。

---

### 4.4 セキュリティ脅威分析と対策 (Threat Model & Mitigations)

| 脅威 ID | 脅威分類 (CWE) | 脅威シナリオ | 具体的防御策 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **THREAT-862-1** | **CWE-400 / CWE-674**<br>Uncontrolled Resource Consumption via Deep Nesting | `[[[[...]]]]` や `{"a":{"a":...}}` のような過度に深い階層を持つ悪意ある JSON を入力し、コールスタック枯渇や OOM を引き起こす攻撃。 | `json-nesting-depth-limit` パラメータ（デフォルト `1000`）を導入し、配列・オブジェクトのネスト開始時にカウントをインクリメント。上限超過時は即座に `json-error` を送出して再帰を中断する。 |
| **THREAT-862-2** | **CWE-400 / CWE-770**<br>Allocation of Resources Without Limits | 巨大な JSON 文字列や無限ストリームを読み込ませ、メモリを枯渇させる攻撃（Character Bomb）。 | `json-number-of-character-limit` パラメータにより読み込み文字数を厳格にトラッキングし、上限超過時に即座に `json-error` を送出する。 |
| **THREAT-862-3** | **CWE-843 / CWE-20**<br>Type Confusion & Malformed JSON Injection | 先行ゼロ `0123`、末尾小数点 `1.`、未エスケープ制御文字 (`U+0000`〜`U+001F`)、未クローズ文字列、不正な後置カンマなどの不正入力を許容して内部状態を破壊する脆弱性。 | RFC 8259 構文規則に厳格に従うステートマシンを実装し、いかなる逸脱も許容せず `json-error`（`read-error?` 適合）を明確な理由文字列付きで送出する。 |
| **THREAT-862-4** | **CWE-176 / CWE-116**<br>Improper Unicode Handling & Lone Surrogates | 不正なサロゲートペア（孤立した上位サロゲート `\uD800` のみ等）による不正 UTF-8 注入や文字化けバイパス。 | サロゲートペアを厳格に検証し、対にならない不正なサロゲートコードポイントは拒絶して `json-error` を送出する。 |
| **THREAT-862-5** | **CWE-190**<br>Numeric Overflow / Truncation | 64-bit を超える超巨大整数や微細な分数が IEEE 754 浮動小数点数への変換によって精度喪失・切り詰められる問題。 | ULisp の完全数値塔（Issue #832 / #861 の Bignum）と連携し、整数表記は多倍長整数としてビット完全・精度無損失でパース・シリアライズを保証する。 |

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/862-implement-srfi-180-json-parser-and-serializer`

1. **基本基盤と例外定義 (`ulisp/lib/json.scm`)**:
   - `define-record-type :json-error` による構造化例外の定義。
   - `json-error?`, `json-error-reason` の実装。
   - `json-null?` の実装 (`(eq? obj 'null)`)。
   - パラメータ `json-nesting-depth-limit` (1000) および `json-number-of-character-limit` (#f) の宣言。
2. **字句解析器・エスケープ処理器の実装**:
   - ポートおよびジェネレータ共通の文字ストリームリーダー。
   - 文字数リミット監視カウンタの実装。
   - 制御文字 (`< #\space`) の拒絶および文字列内エスケープシーケンス (`\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, `\uXXXX`) の完全復元。
   - サロゲートペア復元アルゴリズムの実装。
   - 数値トークン解析器（整数、小数、指数表記の正確な変換）。
3. **ストリーミングイベントプロトコル (`json-generator`, `json-accumulator`)**:
   - 状態機械による逐次トークン yield ジェネレータ。
   - アキュムレータプロシージャによる状態遷移型 JSON 出力。
   - 構造畳み込み手続き `json-fold` の実装。
4. **インメモリ構文木パーサ・シリアライザ**:
   - `json-read`: トークン列から Scheme オブジェクト（ベクタ、シンボルキー連想リスト、スカラー値）を構築。
   - `json-write`: Scheme オブジェクトを走査し、RFC 8259 準拠の文字列を出力。
   - `json-lines-read` および `json-sequence-read` のジェネレータ実装。
   - 高水準変換器 `string->json`, `json->string`, `bytes->json`, `json->bytes` の実装。
5. **モジュール定義ファイル (`.sld`) の配備**:
   - `ulisp/lib/srfi/180.sld`: `(srfi 180)` ライブラリ定義。
   - `ulisp/lib/scheme/json.sld`: `(scheme json)` ライブラリ定義。
   - Traceability ヘッダー (`;;; Traceability: ulisp/docs/ref_r7rs_compliance.md`) および R7RS セクションコメントの付与。
6. **包括的テストスイートの構築 (`ulisp/tests/test_srfi_180.scm`)**:
   - Group 1: プリミティブスカラー値 (`null`, `true`, `false`, 整数, 小数, 負数, 指数)
   - Group 2: 文字列と Unicode エスケープ (`\"`, `\\`, `\n`, `\u0041`, サロゲートペア `\uD83D\uDE00`)
   - Group 3: 配列とオブジェクトのパースとシリアライズ (空配列, 入れ子配列, alist 相互変換)
   - Group 4: 往復テスト (`json->string (string->json s)`)
   - Group 5: ストリーミング API (`json-generator`, `json-accumulator`, `json-fold`)
   - Group 6: JSON Lines (`json-lines-read`) & JSON Sequences (`json-sequence-read`)
   - Group 7: セキュリティ・異常系・境界条件テスト (ネスト上限エラー, 不正サロゲートエラー, 制御文字エラー, 後置カンマエラー)
7. **ビルドシステム統合と品質ゲート検証**:
   - `ulisp/Makefile` への `test_srfi_180` ターゲット追加および `test:` への登録。
   - `ulisp/docs/ref_r7rs_compliance.md` の SRFI 180 ステータスを `◎` に更新。
   - `python3 scripts/verify_r7rs_traceability.py` 100% PASS 確認。
   - `make -C ulisp lint_sexpr` 100% PASS 確認。
   - `make -C ulisp bootstrap` による自己ホスト 5 モジュール並列ビルドの固定点収束確認。
   - トリプル品質ゲート（`make py_compile && make check_format && make static_analysis`）100% PASS。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `(scheme json)` および `(srfi 180)` から全 12 識別子が正常にエクスポートされていること。
- [x] JSON の各データ型（`null`, `true`, `false`, 数値, 文字列, 配列, オブジェクト）が Scheme 型と双方向で正確にマッピングされること。
- [x] Unicode サロゲートペア（絵文字等）が正しく UTF-8 文字にデコードされ、シリアライズ時にも破損しないこと。
- [x] 孤立サロゲートや不正なエスケープシーケンスに対して `json-error?` を満たす例外が送出されること。
- [x] `json-nesting-depth-limit` により、指定された階層数を超える入れ子構造が検知され安全にエラー終了すること。
- [x] `json-generator`, `json-accumulator`, `json-fold` により、ストリーミング形式での読み書きが可能であること。
- [x] `json-lines-read` および `json-sequence-read` が複数レコードを正しく順次処理できること。
- [x] 往復テスト (`(json->string (string->json s))`) において意味論的等価性が保証されること。
- [x] 新規単体テスト `test_srfi_180.scm` の全グループが 100% PASS すること。
- [x] `python3 scripts/verify_r7rs_traceability.py` の監査が 100% PASS すること。
- [x] `make -C ulisp bootstrap` による自己ホスト 5 モジュール並列ビルドが固定点収束（Stage 2 == Stage 3 ビット完全一致）すること。
- [x] `make -C ulisp test` の全テストスイートがエラーなく完走すること。
- [x] トリプル品質ゲート（`make py_compile && make check_format && make static_analysis`）が 100% PASS すること。
- [x] 相対パス規則が厳格に遵守され、絶対パスの混入が 0 件であること。

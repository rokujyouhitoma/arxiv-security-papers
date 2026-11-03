# [DOCS/SPEC] R7RS-small/large および SRFI 原典調査に基づく言語仕様準拠状況リファレンス網羅表の厳格拡充・欠落完全補完 (ID: 700)

## メタデータ
- **Issue ID**: 700
- **種別**: Documentation / Specification Audit
- **優先度**: High
- **ステータス**: Closed (Completed)
- **担当エージェント**: IT Specialist (Programming Languages & Compilers / PLC), Systems Architect, PM
- **作成日**: 2026-11-03
- **完了日**: 2026-11-03
- **ブランチ名**: `docs/700-audit-and-complete-r7rs-compliance-matrix`

---

## 1. 概要 / Summary

`ulisp/docs/ref_r7rs_compliance.md` は、ULisp ネイティブ AOT メタコンパイラにおける Scheme 言語標準準拠状況を明記した正典リファレンスであり、今後のコンパイラおよび標準ライブラリ実装のロードマップと要件定義の基礎となっている。
しかしながら、R7RS-small (2013)、R7RS-large (Red Edition, Tangerine Edition, Yellow / Orange / Hypnos Dockets)、および各種基盤的 SRFI の公式原典（Primary Sources）と対照検証した結果、以下の重大な抜け漏れおよび分類の不整合が確認されたため、完全補完・是正を実施した：

1. **R7RS-small コア仕様の未記載・表記抜けの完全補完**:
   - `features` (§6.14: 有効機能識別子リスト返却) の追加。
   - `input-port-open?`, `output-port-open?` (§6.13.1) の追加。
   - `(scheme cxr)` の全 24 種合成ペアアクセサ (`caaar`〜`cddddr`) の完全明記。
   - `quasiquote`, `unquote`, `unquote-splicing` (§4.2.8) のシンボル名の明示。
   - 補助構文識別子 (`...`, `_`, `=>`, `else`) (§4.2.1 / §4.3) の独立行追加。
   - ライブラリ内包宣言 `include-library-declarations` (§5.6) の追加。
   - 実装済み機能 (`include-ci` [Issue #659], `cond-expand` [Issue #658]) のステータスを **◎** に最新化。
   - **R7RS-small 全 335 識別子の 100% 網羅達成（欠落 0 件を検証スクリプトで実証）**。

2. **R7RS-large のエディション別ライブラリの厳格な再編・拡充**:
   - **Red Edition (Data Structures)**: 正式策定された全 17 ライブラリ (`(scheme list)`, `(scheme vector)`, `(scheme sort)`, `(scheme set)`, `(scheme charset)`, `(scheme hash-table)`, `(scheme ilist)`, `(scheme rlist)`, `(scheme ideque)`, `(scheme text)`, `(scheme generator)`, `(scheme lseq)`, `(scheme stream)`, `(scheme box)`, `(scheme list-queue)`, `(scheme ephemeron)`, `(scheme comparator)`) を正しく網羅。
   - **Tangerine Edition (Numerics & Low-level)**: 正式策定された全 10 ライブラリ (`(scheme division)`, `(scheme bitwise)`, `(scheme fixnum)`, `(scheme flonum)`, `(scheme mapping)`, `(scheme mapping hash)`, `(scheme regex)`, `(scheme generator)` [SRFI 158], `(scheme show)`, `(scheme vector @)`, `(scheme bytevector)`) および Tangerine 義務化の Numeric Tower (Bignums/Rationals/Reals/Complex) を明記。
   - **Yellow Docket (Macros & Syntax)**: `SRFI 8`, `SRFI 26`, `SRFI 31`, `SRFI 61`, `SRFI 139`, `SRFI 188`, `SRFI 210`, `SRFI 212`, `SRFI 213`, `SRFI 219`, `R6RS syntax-case` を網羅追加。
   - **Orange / Hypnos Docket (Advanced Types & I/O)**: `SRFI 48`, `SRFI 166`, `SRFI 175`, `SRFI 178`, `SRFI 180`, `SRFI 189`, `SRFI 190`, `SRFI 196`, `SRFI 207`, `SRFI 209`, `SRFI 214`, `SRFI 217`, `SRFI 222`〜`228` を網羅追加。
   - **実践的・基盤的 SRFI**: `SRFI 0`, `SRFI 2`, `SRFI 6`, `SRFI 9`, `SRFI 11`, `SRFI 16`, `SRFI 18/226`, `SRFI 23`, `SRFI 27`, `SRFI 28`, `SRFI 34`, `SRFI 35`, `SRFI 38`, `SRFI 39`, `SRFI 45`, `SRFI 60`, `SRFI 64`, `SRFI 69`, `SRFI 88`, `SRFI 89`, `SRFI 95`, `SRFI 98`, `SRFI 106`, `SRFI 138`, `SRFI 145`, `SRFI 170`, `SRFI 179`, `SRFI 193`, `SRFI 194`, `SRFI 216` を整理・網羅。

3. **原典（一次情報源）リンク章（第 5 章）の完全新設**:
   - ドキュメント末尾に「5. 原典・仕様規格参照情報源 (Primary Sources & Official Specifications)」を新設し、R7RS-small 公式、WG2 GitHub リポジトリ（エディション・ドケット仕様書）、SRFI 公式サイト、Scheme.org、Gauche / Sagittarius 実装リファレンスの直接ハイパーリンクを完備。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- `ulisp/docs/ref_r7rs_compliance.md`: リファレンス本文、全準拠テーブルの拡張、第 5 章新設
- `docs/issues/closed/700-audit-and-complete-r7rs-compliance-matrix.md`: クローズ済み Issue 定義書
- `docs/issues/README.md`: Issue 台帳

---

## 3. 実装計画と完了条件 (Definition of Done)

1. [x] R7RS-small の全 335 識別子および構文要素とテーブルとの照合・未記載項目の完全補完（欠落 0 件）。
2. [x] R7RS-large Red Edition (全 17 ライブラリ) および Tangerine Edition (全 10 ライブラリ + 数値塔要件) の完全反映。
3. [x] R7RS-large Yellow Docket, Orange/Hypnos Docket, および基盤的 SRFI の網羅的追加。
4. [x] 既存実装済み機能 (`include-ci`, `cond-expand` 等) のステータス最新化。
5. [x] 文末への第 5 章「原典・仕様規格参照情報源」の新設および公式 URL リンクの記載。
6. [x] 相対パスリンク整合性、マークダウン構文、品質ゲート検証 (`make verify_r7rs_traceability`, `make py_compile`) の全項目クリア。

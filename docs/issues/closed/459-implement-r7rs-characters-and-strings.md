# Issue #459: R7RS 文字・文字列プリミティブの網羅的拡充 (R7RS 6.6 & 6.7)

## 1. 概要 (Overview)
ILISP はこれまでにバイトベクタ型、バイナリポート、S式 Datum リーダー、モジュール機構、マクロ展開器などを整備し、高速かつ安全な言語基盤を構築してきた。
現在、文字列操作においては Python `str` との透過的連携や基本的な `string-append` 等が稼働しているが、R7RS-small 仕様の第 6.6 節（Characters）および第 6.7 節（Strings）に規定されている Scheme 標準の文字述語、大文字・小文字比較 (`-ci`), 文字・文字列インデックス操作 (`string-ref`, `string-set!`, `string-copy!`, `string-fill!`), および `(scheme char)` ライブラリの網羅的サポートは未完成である。

論文のテキスト解析、形態素解析、フォーマット整形、および Scheme スクリプトの移植性を完全にするため、本 Issue では R7RS 6.6 / 6.7 節の全文字・文字列プリミティブを実装し、`(scheme char)` モジュールを新設する。

---

## 2. 目的とゴール (Goals)
1. **文字型表現と Reader 構文の拡充 (`ilisp/types.py`, `ilisp/reader.py`)**:
   - `Char` クラスの整備（または Scheme 文字と Python 1文字文字列の統合セマンティクス）
   - 名前付き文字 `#\alarm`, `#\backspace`, `#\delete`, `#\escape`, `#\null`, `#\return`, `#\tab` の Reader 対応
   - 16進数文字リテラル `#\xHHHH` のパース対応
2. **文字操作プリミティブの実装 (`ilisp/env.py`, `ilisp/char.py`)**:
   - 述語: `char?`, `char=?`, `char<?`, `char>?`, `char<=?`, `char>=?`
   - 大文字小文字非区別比較: `char-ci=?`, `char-ci<?`, `char-ci>?`, `char-ci<=?`, `char-ci>=?`
   - 分類述語: `char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`
   - 変換: `digit-value`, `char->integer`, `integer->char`, `char-upcase`, `char-downcase`, `char-foldcase`
3. **文字列操作プリミティブの実装 (`ilisp/env.py`)**:
   - 生成・長: `string?`, `make-string`, `string`, `string-length`
   - 参照・変更: `string-ref`, `string-set!` (可変文字列サポートまたは防御的置換)
   - 比較: `string=?`, `string<?`, `string>?`, `string<=?`, `string>=?`
   - 大文字小文字非区別比較: `string-ci=?`, `string-ci<?`, `string-ci>?`, `string-ci<=?`, `string-ci>=?`
   - コピー・操作: `substring`, `string-copy`, `string-copy!`, `string-fill!`
   - 変換: `string-upcase`, `string-downcase`, `string-foldcase`
   - リスト・ベクタ相互変換: `string->list`, `list->string`, `string->vector`, `vector->string`
   - 反復・写像: `string-map`, `string-for-each`
4. **モジュールシステムへの登録 (`ilisp/module.py`)**:
   - `(scheme char)` ライブラリを新設し、Unicode / CI 関連の文字・文字列手続きをエクスポート。
   - `(scheme base)` に基本文字・文字列手続きをエクスポート。
5. **テストスイートの整備 (`tests/ilisp/test_characters_and_strings.py`)**:
   - 全文字リテラル、文字述語、文字列比較、大文字小文字変換、可変操作の網羅的テスト。
6. **仕様書・DoD の更新 (`ilisp/docs/SPEC_R7RS.md`)**:
   - 第6.6節および第6.7節のステータスを 100% 完全準拠へ更新。

---

## 3. 完了条件 (Definition of Done)
- [x] Reader が名前付き文字リテラル (`#\tab`, `#\space`, `#\newline` 等) および `#\x...` を正しくパースできる。
- [x] R7RS 6.6 節の全文字プリミティブ（比較、述語、整数変換、大文字小文字変換）が動作する。
- [x] R7RS 6.7 節の全文字列プリミティブ（`make-string`, `string-ref`, `string-set!`, `substring`, `string-copy!`, `string-fill!`, `string-map` 等）が動作する。
- [x] `(scheme char)` モジュールが定義され、R7RS 規定の手続きが正しくインポートできる。
- [x] `tests/ilisp/test_characters_and_strings.py` の全テストが 100% PASS すること。
- [x] 既存の ILISP 全テストスイートが 100% PASS を維持すること。
- [x] `flake8` および `mypy --strict` をエラー 0 件でパスすること。
- [x] `ilisp/docs/SPEC_R7RS.md` の文字・文字列セクションのステータスが更新されていること。

---

## 4. 実装結果サマリー (Implementation Results)
- **`Char` 型 & Reader 構文の拡充 (`ilisp/types.py`, `ilisp/reader.py`)**:
  - `Char` クラスを実装し、Scheme の文字リテラルと文字列を型安全に分離。
  - `#\alarm`, `#\backspace`, `#\delete`, `#\escape`, `#\null`, `#\newline`, `#\return`, `#\space`, `#\tab` の標準名前付き文字、および `#\xHHHH` 16進数文字リテラルをパース可能に。
  - Python ゼロコピー透過相互運用のため、Python 1文字 `str` との等価比較を自然にサポート。
- **可変文字列型 `MutableString` (`ilisp/types.py`)**:
  - R7RS 仕様に準拠し、リテラル文字列はイミュータブル `str`、`make-string` や `string-copy` で動的生成された文字列は `MutableString` として扱い、不変文字列への変更は厳格に拒否する安全性を確立。
- **R7RS 6.6 & 6.7 プリミティブ群 (`ilisp/char.py`, `ilisp/env.py`)**:
  - 文字比較 (`char=?`, `char<?`, `char>?`, `char<=?`, `char>=?`, `char-ci*`)
  - 文字分類 (`char-alphabetic?`, `char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`, `digit-value`)
  - 文字変換 (`char->integer`, `integer->char`, `char-upcase`, `char-downcase`, `char-foldcase`)
  - 文字列生成・インデックス (`make-string`, `string`, `string-length`, `string-ref`, `string-set!`)
  - 文字列比較 (`string=?`, `string<?`, `string>?`, `string<=?`, `string>=?`, `string-ci*`)
  - 部分文字列・コピー (`substring`, `string-copy`, `string-copy!`, `string-fill!`)
  - 相互変換・写像 (`string->list`, `list->string`, `string->vector`, `vector->string`, `string-map`, `string-for-each`)
  - 再帰的構造等価性述語 `equal?` を正式追加。
- **モジュール機構統合 (`ilisp/module.py`)**:
  - `(scheme char)` ライブラリを新設し、R7RS 7.1.3 節に規定された全手続きをエクスポート。
- **品質・テスト検証**:
  - `tests/ilisp/test_characters_and_strings.py`: 全 26 件 100% PASS。
  - `tests/ilisp/`: 全 162 件 100% PASS。
  - `flake8`: 0 警告、`mypy --strict`: 0 エラー。


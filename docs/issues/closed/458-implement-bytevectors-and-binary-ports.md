# Issue #458: R7RS バイトベクタ型 (#u8) とバイナリポートシステムの実装

## 1. 概要 (Overview)
ILISP はこれまでにテキストポート、文字列ポート、ファイルポート、S式 Datum リーダーを整備し、Scheme テキストプログラムの入出力を高度にサポートした。
しかし、arXiv 論文 PDF のバイナリ構文解析、画像・フォント抽出、暗号ハッシュ計算、および高効率なネットワーク通信を行うためには、生バイト列を $O(1)$ で直接操作可能な **バイトベクタ型 (`Bytevector`, `#u8(...)`)** および **バイナリポートシステム (`(scheme base)`)** が不可欠である。

本 Issue では、R7RS-small 仕様の第 6.9 節（Bytevectors）および第 6.13 節（Binary input and output）に準拠したバイトベクタ型およびバイナリ入出力ポートシステムを設計・実装し、ILISP におけるバイナリ・マルチメディア・暗号データ処理の基盤を完成させる。

---

## 2. 目的とゴール (Goals)
1. **バイトベクタデータ構造の実装 (`ilisp/types.py`)**:
   - `Bytevector` クラスの実装（内部表現に Python `bytearray` を採用し、可変・高速操作を実現）
   - リーダー表現 `#u8(byte ...)` の `__repr__` および `__str__`
   - インデックス参照・代入・長さ・等価比較
2. **手書き Reader の `#u8(...)` リテラル対応 (`ilisp/reader.py`)**:
   - ハッシュリテラル処理において `#u8(...)` を検出し、`Bytevector` インスタンスとしてパース
3. **バイトベクタ標準プリミティブ群の実装 (`ilisp/env.py`)**:
   - `bytevector?`: バイトベクタ判定述語
   - `make-bytevector`: 指定長・初期値でのバイトベクタ生成
   - `bytevector`: 可変長引数からのバイトベクタ生成
   - `bytevector-length`: 長さ取得
   - `bytevector-u8-ref`, `bytevector-u8-set!`: 1 バイト要素の参照と破壊的代入 (0〜255 の範囲チェック付き)
   - `bytevector-copy`, `bytevector-copy!`: 部分複製およびインプレースブロック転送
   - `bytevector-append`: 複数バイトベクタの連結
   - `utf8->string`, `string->utf8`: UTF-8 バイト列と Scheme 文字列の相互変換
4. **バイナリポートシステムの実装 (`ilisp/port.py`)**:
   - `BinaryInputPort`, `BinaryOutputPort` 基底クラス
   - `BinaryFileInputPort`, `BinaryFileOutputPort`: ファイルバイナリ入出力
   - `BytesInputPort`, `BytesOutputPort`: インメモリバイトベクタ入出力
   - 述語: `binary-port?`
   - ファイル操作: `open-binary-input-file`, `open-binary-output-file`
   - インメモリ操作: `open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector`
   - 1バイト入出力: `read-u8`, `peek-u8`, `u8-ready?`, `write-u8`
   - ブロック入出力: `read-bytevector`, `read-bytevector!`, `write-bytevector`
5. **Backend A (Python AST コンパイラ) への統合 (`ilisp/backend/py_codegen/compiler.py`)**:
   - `#u8(...)` リテラルの Python AST コード生成対応
6. **テストスイートの整備 (`tests/ilisp/test_bytevectors_and_binary_ports.py`)**:
   - リテラルパース、境界値（0, 255, 範囲外エラー）、部分コピー・破壊的代入の検証
   - UTF-8 相互変換（日本語文字列含む）の検証
   - ファイルバイナリ書き込み・読み込みのラウンドトリップ検証
   - インメモリバイナリポートによる動的バッファリング検証
7. **ドキュメント・仕様準拠マトリクスの更新**:
   - `ilisp/docs/SPEC_R7RS.md` のバイトベクタカテゴリ（6.9）のステータスを 0% から 100% 完全準拠へ更新。

---

## 3. 完了条件 (Definition of Done)
- [x] `ilisp/types.py` に `Bytevector` クラスが実装されている。
- [x] `ilisp/reader.py` が `#u8(...)` 記法をパースできる。
- [x] `ilisp/env.py` に R7RS 6.9 節の全 11 種類のバイトベクタプリミティブが実装・登録されている。
- [x] `ilisp/port.py` にバイナリファイルポートおよびインメモリバイトベクタポート、1バイト/ブロック I/O 手続きが実装されている。
- [x] `(scheme base)` にバイトベクタおよびバイナリポート関連手続きがエクスポートされている。
- [x] `tests/ilisp/test_bytevectors_and_binary_ports.py` に網羅的なテストが追加され、全テストが 100% PASS すること。
- [x] 静的解析（flake8, mypy --strict）をエラー 0 件でパスすること。
- [x] `SPEC_R7RS.md` の仕様準拠状況が更新されていること。

---

## 4. 実装結果サマリー (Implementation Results)
- **`Bytevector` 型 & Reader リテラル**:
  - `ilisp/types.py`: 内部表現に Python `bytearray` を採用し、`Bytevector` クラス、`is_bytevector` 判定関数を実装。`#u8(1 2 3)` 形式の文字列表現および等価性比較を完備。
  - `ilisp/reader.py`: `#u8(...)` リーダー構文をサポート。
  - `ilisp/evaluator.py`: `Bytevector` を自己評価リテラル型としてサポート。
  - `ilisp/backend/py_codegen/compiler.py`: `#u8(...)` リテラルの Python AST コード生成に対応。
- **R7RS 6.9 バイトベクタ操作プリミティブ**:
  - `bytevector?`, `make-bytevector`, `bytevector`, `bytevector-length`, `bytevector-u8-ref`, `bytevector-u8-set!`, `bytevector-copy`, `bytevector-copy!`, `bytevector-append`, `utf8->string`, `string->utf8` の 11 種類を実装。
- **R7RS 6.13 バイナリポート & 入出力**:
  - `BinaryInputPort`, `BinaryOutputPort`, `BytesInputPort`, `BytesOutputPort`, `BinaryFileInputPort`, `BinaryFileOutputPort` を設計。
  - `binary-port?`, `open-binary-input-file`, `open-binary-output-file`, `open-input-bytevector`, `open-output-bytevector`, `get-output-bytevector`, `read-u8`, `peek-u8`, `u8-ready?`, `read-bytevector`, `read-bytevector!`, `write-u8`, `write-bytevector` を実装・エクスポート。
- **品質・テスト検証**:
  - `tests/ilisp/test_bytevectors_and_binary_ports.py`: 18 件のテストすべて 100% PASS。
  - `tests/ilisp/`: 全 136 件テスト 100% PASS。
  - `flake8`: 0 警告、`mypy --strict`: 0 エラー。


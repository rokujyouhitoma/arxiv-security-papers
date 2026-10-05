# ILISP Python 双方向ゼロコピー相互運用仕様書 (Python Interop Specification)

本ドキュメントは、ILISP (Intelligence LISP) と Python ランタイム間における **双方向・摩擦ゼロ・ゼロコピー（Zero-Copy）相互運用プロトコル** の詳細技術仕様を規定します。

---

## 1. 概要と設計思想

ILISP は AI/NLP、機械学習、セキュリティ研究における現代の Python エコシステム（PyTorch, Hugging Face Transformers, NumPy, requests 等）をそのまま第一級の構成要素として活用できるよう設計されています。

従来の Lisp-Python ブリッジで頻発する以下の課題を抜本的に解決します：
1. **$O(N)$ ディープコピー問題の根絶**: 巨大なリストや配列の相互受け渡し時にメモリコピーを発生させない。
2. **型インピーダンス・ミスマッチの解消**: Scheme の第一級シンボル・ペア構造と Python のオブジェクト・辞書・イテレータを双方向で透過変換。
3. **双方向インポート**: ILISP から Python モジュールを直接インポート可能であると同時に、Python 側からも ILISP モジュールを通常の Python モジュールとしてインポート可能。

---

## 2. $O(1)$ ゼロコピープロトコル (`SequenceView`)

Scheme の伝統的な連結リスト（Cons セル）と Python の連続メモリアレイ（`list`, `tuple`）の間で、メモリ複写を行わずに相互アクセスを実現する核心機構が **`SequenceView`** です。

### 2.1 データ構造と計算量

```python
class SequenceView:
    __slots__ = ("_seq", "_offset")
    def __init__(self, seq: Sequence[Any], offset: int = 0):
        self._seq = seq
        self._offset = offset

    def car(self) -> Any:
        # O(1) 直接インデックスアクセス
        return self._seq[self._offset]

    def cdr(self) -> Any:
        # O(1) スライス複製なしのオフセット移動
        if self._offset + 1 >= len(self._seq):
            return ()
        return SequenceView(self._seq, self._offset + 1)
```

- **$O(1)$ 先頭要素取得 (`car`)**: Python 配列の現在オフセット位置を直接参照。
- **$O(1)$ 残余リスト取得 (`cdr`)**: 新たなメモリ配列を確保せず、`offset + 1` を保持する新しい軽量ビューオブジェクトのみを生成。
- **数万件の arXiv 論文データ処理**: メモリフットプリントを最小限に抑え、キャッシュ局所性を維持しながら Lisp の高階関数（`map`, `for-each`, `filter`）で走査可能。

---

## 3. ILISP から Python へのアクセス仕様

### 3.1 `import-python` 構文とマクロ展開

Python の標準ライブラリおよびサードパーティ製パッケージを ILISP の環境へ直接導入します。
`import-python` は独立した標準拡張モジュール `(ilisp python)` 内で高次衛生的マクロとして実装されており、Scheme のコア評価器を汚染することなく低レベルのプリミティブ (`py-import`, `py-get`) へ展開されます。

```scheme
(import (scheme base)
        (ilisp python))

;; 1. モジュール全体をエイリアス付きでインポート
(import-python (torch :as th)
               (transformers AutoTokenizer))
;; 展開後:
;;   (define th (py-import 'torch))
;;   (define AutoTokenizer (py-get (py-import 'transformers) 'AutoTokenizer))

;; 2. 特定の関数やクラスを直接インポート
(import-python (math sqrt sin pi)
               (pathlib Path)
               (json loads dumps))

;; 3. メンバのエイリアス指定
(import-python (transformers (AutoTokenizer :as Tok))
               (numpy (ndarray :as NDArray)))

;; 4. 平坦形式のエイリアス指定
(import-python (os path :as ospath))
```

#### エラーハンドリング・例外セマンティクス
指定された Python モジュールがインストールされていない場合や、指定された属性・クラスが存在しない場合、低レベルの Python 例外（`ModuleNotFoundError`, `AttributeError`）は Scheme の条件付き例外 `&error-object(kind=import)` へと自動昇格されます。これにより、Scheme 側の `guard` や `with-exception-handler` で安全に捕捉可能です。

```scheme
(guard (err
        ((and (error-object? err) (eq? (error-object-kind err) 'import))
         (display "Optional library is not installed: ")
         (display (error-object-message err))
         (newline)
         #f))
  (import-python (torch :as th)))
```

### 3.2 透過呼び出し手続き (`py-call`, `py-get`, `py-set!`)

- **`(py-call obj method/fn arg ...)`**:
  - Python の関数・メソッドを直接実行。`obj` がすでに Callable の場合、メソッド名を省略して直接呼び出し可能。
  - キーワード引数は `:keyword value` ペアとして指定可能。
- **`(py-get obj attr-symbol)`**:
  - Python オブジェクトの属性または辞書キーを取得。
- **`(py-set! obj attr-symbol value)`**:
  - Python オブジェクトの属性または辞書キーを更新。

```scheme
(define (fetch-and-parse-arxiv arxiv-id)
  (let* ((url (string-append "https://export.arxiv.org/api/query?id_list=" arxiv-id))
         (resp (py-call requests 'get url))
         (status (py-get resp 'status_code)))
    (if (= status 200)
        (py-get resp 'text)
        (error "Failed to fetch arXiv metadata" arxiv-id status))))
```

### 3.3 パイプライン・スレッディングマクロ (`->>` / `|\|>>|`)

データ変換パイプラインを直感的に記述するためのスレッディングマクロを提供します：

```scheme
;; 第一引数を後続の各式における「最後の引数」として順次渡す
(->> (py-call requests 'get "https://example.com/api")
     (py-get 'text)
     (py-call json 'loads))

;; R7RS シンボルエスケープ表記 |\|>>| も互換性のためエイリアス提供
(|\|>>| '(1 2 3 4)
        (map (lambda (x) (* x 2)))
        (filter (lambda (x) (> x 4))))
;; => (6 8)
```

### 3.4 Clojure 風糖衣構文とドット記法シンボルの動的自動解決 (Issue 481)

Python 相互運用の記述性を高めるため、ILISP では Clojure ライクなドット記法およびドットを含むシンボルの動的インポート解決を標準サポートしています。

#### 1. メソッド呼び出し構文 (`.method` / `.`)
- **`(.method obj arg ...)`**: オブジェクト `obj` のメソッド `method` を呼び出します（`(py-call obj 'method arg ...)` に等価）。
- **`(. obj method arg ...)`** または **`(. obj (method arg ...))`**: プリミティブなドット形式。

```scheme
(.upper "hello")              ;; => "HELLO"
(.split "2026-10-05" "-")     ;; => ("2026" "10" "05")
(.strip "  arXiv security  ") ;; => "arXiv security"

;; スレッディングマクロとのシームレスな融合
(->> "  arXiv,security,papers  "
     .strip
     (.split ",")
     (map .strip))
```

#### 2. プロパティ・属性アクセス構文 (`.-attr`)
- **`(.-attr obj)`** または **`(. obj -attr)`**: 属性・フィールド値を取得（`(py-get obj 'attr)` に等価）。
- **`(.-attr obj val)`** または **`(. obj -attr val)`**: 属性値を更新（`(py-set! obj 'attr val)` に等価）。

```scheme
(.-status_code resp)          ;; => 200
(.-shape tensor)              ;; => (32 512)
(. resp -headers)             ;; => HTTP ヘッダー辞書
```

#### 3. ドット記法シンボルの自動解決 (Auto-Desugaring)
シンボル名にピリオド（`.`）が含まれる場合、明示的な `import-python` を行わなくても自動的にモジュールをインポート・解決します。
- スコープ内にルート変数が存在する場合、そのオブジェクトの属性を連続走査します。
- スコープ内に存在しない場合、最長一致の Python モジュールを動的にインポートし、残余属性を解決します。

```scheme
;; 未インポートのモジュールから直接参照・呼び出し
math.pi                       ;; => 3.141592653589793
(math.sqrt 49)                ;; => 7.0
(os.getcwd)                   ;; => カレントディレクトリ文字列
(os.path.join "data" "raw")   ;; => "data/raw"

;; ローカルオブジェクトの属性アクセス
(define (get-status response)
  response.status_code)
```

---

## 4. Python 側からの ILISP 利用仕様

### 4.1 直接評価と対話セッション (`ilisp.eval` / `ilisp.Evaluator`)

Python 側から ILISP の式を即座にワンライナーで評価したり、持続的な状態（変数・関数定義）を持つセッション環境を対話的に利用できます。

```python
import ilisp

# 1. ワンライナー直接評価 (即時実行)
result = ilisp.eval("(+ 1 2 3 4 5)")
print(result)  # => 15

# Python AST トランスパイラバックエンドでの実行
result_fast = ilisp.eval("(* 6 7)", backend="py_ast")
print(result_fast)  # => 42

# 2. 持続的セッション評価 (Evaluator)
evaluator = ilisp.Evaluator()

# 変数定義と計算
evaluator.eval("(define base-threat-score 85)")
evaluator.eval("(define (calc-adjusted-score factor) (* base-threat-score factor))")

# Python 側から Scheme 手続きの直接実行
final_score = evaluator.call("calc-adjusted-score", 1.2)  # スネークケース "calc_adjusted_score" でも呼出可能
print(final_score)  # => 102.0

# 変数のバインドと取得 (ケバブケース／スネークケース自動解決)
evaluator.set("api_key", "sec-token-12345")
print(evaluator.get("api-key"))  # => "sec-token-12345"
```

### 4.2 モジュールの動的ロード (`ilisp.load_ilisp_module`)

外部の `.ilisp` または `.scm` ファイルを透過プロキシ（`IlispModuleProxy`）としてロードし、Python の属性アクセス形式で関数や定数へ直接アクセス可能です。

```python
from ilisp import load_ilisp_module

# モジュールファイルの動的ロード
sec_module = load_ilisp_module("path/to/threat_analyzer.ilisp")

# Scheme のケバブケース識別子 (例: analyze-cve) を Python スネークケースで透過呼出
report = sec_module.analyze_cve("CVE-2026-12345")
print(sec_module.base_score)

# モジュール名前空間内での追加式評価
custom_metric = sec_module.eval("(calculate-cvss base-score 1.5)")
```

### 4.3 透過インポート機構 (`sys.meta_path`)

`ilisp.register_import_hook()` を呼び出すことで、Python の標準 `import` 構文を用いて `sys.path` 上の `.ilisp` / `.scm` ファイルを通常の Python モジュールと同様に透過的にインポートできます。

```python
import ilisp

# インポートフックの有効化
ilisp.register_import_hook()

# 通常の Python モジュールとしてインポート
import threat_analyzer  # threat_analyzer.ilisp を自動解決

# モジュール属性や関数を直接利用
print(threat_analyzer.app_version)
result = threat_analyzer.calculate_hash("data")

# フックの安全な解除
ilisp.unregister_import_hook()
```

---

## 5. 型マッピング・変換マトリクス

| ILISP / Scheme 型 | Python 型 | 変換規則・セマンティクス |
| :--- | :--- | :--- |
| 整数 (`123`) | `int` | 同一（任意精度長整数） |
| 有理数 (`1/3`) | `fractions.Fraction` | 完全精度保持・相互演算可能 |
| 実数 (`3.14`) | `float` | IEEE 754 64bit 倍精度浮動小数点数 |
| 複素数 (`1+2i`) | `SchemeComplex` / `complex` | `real_val`/`imag_val` 厳密保持、Python `complex` と相互運用 |
| 文字列 (`"abc"`) | `str` | Unicode 文字列（ゼロコピー参照） |
| 文字 (`#\a`) | `ilisp.types.Char` (`str`) | 長さ 1 の文字オブジェクト |
| シンボル (`'foo`) | `ilisp.types.Symbol` | インターン済みシンボルオブジェクト |
| 真偽値 (`#t`, `#f`) | `bool` (`True`, `False`) | 直接対応（Scheme では `#f` のみ偽） |
| 空リスト (`'()`) | `()` (`tuple`) / `None` | 空タプルまたは Scheme 固有 Nil |
| ペア・リスト (`'(1 2 3)`) | `ilisp.types.Cons` / `SequenceView` | 双方向 $O(1)$ 走査 |
| ベクタ (`#(1 2 3)`) | `ilisp.types.Vector` (`list`) | 動的配列 |
| バイトベクタ (`#u8(1 2 3)`) | `bytearray` / `bytes` | 高速バイナリバッファ |
| 手続き (`(lambda ...)`)| `ilisp.types.Procedure` (`Callable`) | Python 側から `proc(*args)` で呼出可能 |

---

## 6. 関連ドキュメント体系

- [README.md](README.md): ILISP 概要・クイックスタート・3本柱アーキテクチャ
- [SPEC_R7RS.md](SPEC_R7RS.md): R7RS-small 全203機能の仕様準拠マトリクス & chibi-scheme 公式テスト 100% 適合検証レポート
- [MACROS_AND_CONDITIONS.md](MACROS_AND_CONDITIONS.md): Scope Sets マクロ & 現場復帰コンディション & テストハーネス仕様
- [BOOTSTRAP.md](BOOTSTRAP.md): Kernel ILISP 仕様 & 3段階ブートストラップ連鎖 & 不動点検証
- [DSN-31 包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md): ILISP R7RS コアアーキテクチャ包括設計仕様書

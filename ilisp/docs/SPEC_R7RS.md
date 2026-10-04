# ILISP R7RS-small 仕様準拠マトリクス (Specification Matrix)

ILISP は、世界標準規格 **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme)** を基盤言語仕様として採用します。

本ドキュメントは、R7RS-small で規定された各言語機能・ライブラリのサポート計画および ILISP 独自拡張を定義します。

---

## 1. コア言語仕様サポート状況

| カテゴリ | R7RS 規格機能 | ILISP サポート方針 | 処理系工学的詳細・備考 |
| :--- | :--- | :---: | :--- |
| **式 (Expressions)** | `quote`, `lambda`, `if`, `set!` | ✅ 完全準拠 | 言語コアの基本形式（Kernel ILISP 核） |
| | `cond`, `case`, `and`, `or`, `when`, `unless` | ✅ 完全準拠 | 衛生的マクロ展開による `if`/`lambda` への脱糖 |
| | `let`, `let*`, `letrec`, `letrec*` | ✅ 完全準拠 | レキシカルスコープの厳格保証（相互再帰バインド） |
| | `begin`, `do` | ✅ 完全準拠 | 逐次実行・反復ループ |
| **データ型** | 真偽値 (`#t`, `#f`) | ✅ 完全準拠 | Python `bool` / C `stdbool` と直接マッピング |
| | 数値 (整数, 浮動小数, 有理数) | ✅ 順次対応 | Python `int`/`float` 連携、完全数値タワー対応 |
| | 文字 (`#\a`, `#\newline`) | ✅ 完全準拠 | Unicode 準拠文字コードポイント |
| | 文字列 (Strings) | ✅ 完全準拠 | 不変・可変文字列操作 |
| | シンボル (Symbols) | ✅ 完全準拠 | グローバル・インターン保証 |
| | ペアとリスト (`cons`, `car`, `cdr`) | ✅ 完全準拠 | 不動点走査の核（不変 Cons セル） |
| | ベクタ (`#(1 2 3)`) | ✅ 完全準拠 | ランダムアクセス $O(1)$ 配列 |
| | バイトベクタ (`#u8(...)`) | ✅ 完全準拠 | バイナリパース・PDF/フォント解析用 |
| **制御構文** | 末尾呼び出し最適化 (TCO) | ✅ 必須要件 | **ハイブリッド TCO**: 自己再帰は Python/C ループ展開（ゼロコスト）、相互再帰は軽量トランポリン |
| | 継続 (`call/cc`, `dynamic-wind`) | ✅ 階層的準拠 | **Python**: One-shot 脱出継続（例外ベース・ゼロコスト）<br>**C99**: スタック複写による完全 Multishot 継続 |
| **マクロ** | `define-syntax`, `syntax-rules` | ✅ 必須要件 | **Scope Sets アルゴリズム** 採用。変数捕捉の完全防止とフェーズ分離 |
| | `syntax-error` | ✅ 完全準拠 | コンパイル時診断・ソース位置（Span）追跡 |
| **モジュール** | `define-library`, `import`, `export` | ✅ 必須要件 | `(scheme base)` 等の完全分離・Python 透過インポート |

---

## 2. 標準ライブラリ一覧 (`(scheme ...)`)

- `(scheme base)`: 基本操作・リスト・制御構造・マクロ
- `(scheme write)`: `display`, `write`
- `(scheme read)`: S式パーサ・リーダー（Datum リーダー）
- `(scheme file)`: ファイル入出力
- `(scheme process-context)`: 環境変数・コマンドライン引数
- `(scheme time)`: 高精度タイマー
- `(scheme char)`: 文字操作

---

## 3. ILISP 独自拡張ライブラリ (`(ilisp ...)`)

- `(ilisp python)`:
  - `import-python`: Python モジュールのインポート
  - `py-call`: Python オブジェクトのメソッド呼出・プロパティ参照
  - `py-get`, `py-set!`: 属性・辞書キーアクセス
  - `py-for-each`, `py-map`: **Lazy View (Zero-Copy)** 走査イテレータ
  - `py->list`, `list->py`: 明示的ディープコピー変換
- `(ilisp condition)`:
  - `restart-case`, `handler-bind`, `invoke-restart`: 現場復帰型コンディション
  - `boundary-guard`: Python 例外をインターセプトし再試行 Thunk を保持したコンディション送出
- `(ilisp okf)`:
  - S-OKF 構文、YAML フロントマター抽出、Markdown AST 変換
- `(ilisp pipeline)`:
  - `|>>` (スレッディングマクロ), レート制限・指数バックオフ修飾子
- `(ilisp logic)`:
  - miniKanren 記号推論エンジン (ATT&CK / STRIDE 知識オントロジー連動)

---

## 4. バックエンド実装マトリクス

| 機能 | Backend A: Python AST | Backend B: Native C99 AOT | Backend C: Rust Standalone VM |
| :--- | :--- | :--- | :--- |
| **主目的** | 開発 DX・Python ゼロ摩擦連携 | 外部依存ゼロの単一バイナリ生成 | No-GIL マルチコア並列・超高速実行 |
| **TCO** | 自己末尾ループ化＋トランポリン | C99 `goto` / Chenc トランポリン | レジスタ/スタック VM ループ |
| **継続** | One-shot 脱出継続 (例外ベース) | Multishot 一級継続 (MTA法) | 仮想マシンスタックフレーム保持 |
| **メモリ管理** | CPython 参照カウント＋GC | 自己完結 ARC / 2空間コピーGC | NaN-Boxing 64bit 値＋並列 GC |
| **Python Interop**| 直接 Python 呼出 ($O(1)$) | CPython C-API / ctypes | PyO3 ネイティブ Extension |

# ILISP R7RS-small 仕様準拠マトリクス (Specification Matrix)

ILISP は、世界標準規格 **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme)** を基盤言語仕様として採用します。

本ドキュメントは、R7RS-small で規定された各言語機能・ライブラリのサポート計画および ILISP 独自拡張を定義します。

---

## 1. コア言語仕様サポート状況

| カテゴリ | R7RS 規格機能 | ILISP サポート方針 | 備考 |
| :--- | :--- | :---: | :--- |
| **式 (Expressions)** | `quote`, `lambda`, `if`, `set!` | ✅ 完全準拠 | 言語コアの基本形式 |
| | `cond`, `case`, `and`, `or`, `when`, `unless` | ✅ 完全準拠 | マクロ展開およびコア変換 |
| | `let`, `let*`, `letrec`, `letrec*` | ✅ 完全準拠 | レキシカルスコープの厳格保証 |
| | `begin`, `do` | ✅ 完全準拠 | 逐次実行・繰り返し |
| **データ型** | 真偽値 (`#t`, `#f`) | ✅ 完全準拠 | Python `bool` / C `stdbool` と直接マッピング |
| | 数値 (整数, 浮動小数, 有理数) | ✅ 順次対応 | Python `int`/`float` 連携、完全数値タワー対応 |
| | 文字 (`#\a`, `#\newline`) | ✅ 完全準拠 | Unicode 準拠 |
| | 文字列 (Strings) | ✅ 完全準拠 | 不変・可変文字列操作 |
| | シンボル (Symbols) | ✅ 完全準拠 | インターン保証 |
| | ペアとリスト (`cons`, `car`, `cdr`) | ✅ 完全準拠 | 不動点走査の核 |
| | ベクタ (`#(1 2 3)`) | ✅ 完全準拠 | ランダムアクセス配列 |
| | バイトベクタ (`#u8(...)`) | ✅ 完全準拠 | バイナリパース・PDF解析用 |
| **制御構文** | 末尾呼び出し最適化 (TCO) | ✅ 必須要件 | スタックフレーム消費 $O(1)$ 保証 |
| | 継続 (`call/cc`, `dynamic-wind`) | ✅ 完全準拠 | トランポリン / CPS 変換 |
| **マクロ** | `define-syntax`, `syntax-rules` | ✅ 必須要件 | 衛生的一致・変数捕捉防止 |
| | `syntax-error` | ✅ 完全準拠 | マクロ展開時診断 |
| **モジュール** | `define-library`, `import`, `export` | ✅ 必須要件 | `(scheme base)` 等の分離 |

---

## 2. 標準ライブラリ一覧 (`(scheme ...)`)

- `(scheme base)`: 基本操作・リスト・制御構造・マクロ
- `(scheme write)`: `display`, `write`
- `(scheme read)`: S式パーサ・リーダー
- `(scheme file)`: ファイル入出力
- `(scheme process-context)`: 環境変数・コマンドライン引数
- `(scheme time)`: 高精度タイマー
- `(scheme char)`: 文字操作

---

## 3. ILISP 独自拡張ライブラリ (`(ischeme ...)`)

- `(ischeme python)`:
  - `import-python`: Python モジュールのインポート
  - `py-call`: Python オブジェクトのメソッド呼出・プロパティ参照
  - `py->list`, `list->py`: 透過型変換
- `(ischeme condition)`:
  - `restart-case`, `handler-bind`, `invoke-restart`: 現場復帰型コンディション
- `(ischeme okf)`:
  - S-OKF 構文、YAML フロントマター抽出、Markdown AST 変換
- `(ischeme pipeline)`:
  - `|>>` (スレッディングマクロ), レート制限・指数バックオフ修飾子
- `(ischeme logic)`:
  - miniKanren 記号推論エンジン (ATT&CK / STRIDE 知識オントロジー連動)

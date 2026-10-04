# [DSN-31] ILISP (Intelligence LISP) R7RS コアアーキテクチャ包括設計仕様書
## 〜 R7RS-small Scheme準拠・Python双方向ゼロコピー相互運用・C99 AOT / Rust VM 3本柱バックエンド・Scope Setsマクロ・3段階セルフホスティングブートストラップ連鎖 〜

- **文書番号**: `DSN-31`
- **文書ステータス**: `APPROVED`
- **対象サブシステム**:
  - `ilisp/` (ILISP 言語処理系基盤)
  - `ilisp/compiler/` (S式 Reader, Tokenizer, AST, Scope Sets Macro Expander)
  - `ilisp/backend/py_codegen/` (Python AST コード生成器 / Zero-Copy Lazy View)
  - `ilisp/backend/c_codegen/` (Native C99 AOT コード生成器 / Clang LLVM 連携 / 自己完結 ARC)
  - `ilisp/vm/` (Rust Standalone Bytecode VM / NaN-Boxing / No-GIL 並行性 / PyO3)
  - `ilisp/runtime/` (ハイブリッド TCO, 階層的 call/cc, 現場復帰コンディション)
  - `ilisp/stdlib/` (R7RS 標準ライブラリ & ILISP 拡張モジュール)
  - `ilisp/docs/` (ILISP 言語固有ドキュメント体系)
- **関連設計書**:
  - [DSN-01 (High-Level Architecture)](DSN-01-high_level_design.md)
  - [DSN-24 (Unified Management CLI & Database Shell)](DSN-24-unified_management_cli_and_interactive_database_shell.md)
  - [DSN-25 (Pure-Python Packrat PEG Parser Engine & Bootstrap)](DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [DSN-29 (Python-LISP Integrated Architecture Specification - pylisp)](DSN-29-python_lisp_integrated_architecture_specification.md)
- **【主査・報告】 IT Specialist (Programming Languages & Compilers / PLC) / Systems Architect (SA)**
- **【共同主査】 Project Manager (PM) / Software Development (SWD) / Software Quality Assurance Specialist (QA)**
- **【参画・協調】 16 大専門エージェント全員 (PM, SEC, SA, QA, DBA, NET, NLP, STR, SM, EMB, AUD, DES, EDU, SWD, APS, PLC)**

---

## 体系目次

- [0. 概要と基本方針 (Executive Summary)](#0-概要と基本方針-executive-summary)
- [1. 言語哲学とアイデンティティ (Intelligence + IKE + AI + LISP)](#1-言語哲学とアイデンティティ-intelligence--ike--ai--lisp)
- [2. R7RS-small 言語仕様と処理系工学的精緻化](#2-r7rs-small-言語仕様と処理系工学的精緻化)
  - [2.1 言語コアの最小直交性](#21-言語コアの最小直交性)
  - [2.2 Scope Sets アルゴリズムによる衛生的マクロとフェーズ分離](#22-scope-sets-アルゴリズムによる衛生的マクロとフェーズ分離)
  - [2.3 ハイブリッド末尾呼出最適化 (Hybrid TCO)](#23-ハイブリッド末尾呼出最適化-hybrid-tco)
  - [2.4 階層的継続セマンティクス (Hierarchical call/cc)](#24-階層的継続セマンティクス-hierarchical-callcc)
- [3. 3本柱の実行バックエンド体系 (The Three Pillars of Execution)](#3-3本柱の実行バックエンド体系-the-three-pillars-of-execution)
  - [3.1 Backend A: Python AST トランスパイラ (Python Interop モード)](#31-backend-a-python-ast-トランスパイラ-python-interop-モード)
  - [3.2 Backend B: Native C99 AOT コンパイラ (Clang/LLVM 連携 & 自己完結 ARC)](#32-backend-b-native-c99-aot-コンパイラ-clangllvm-連携--自己完結-arc)
  - [3.3 Backend C: Rust Standalone Bytecode VM (No-GIL並行性 & NaN-Boxing & PyO3)](#33-backend-c-rust-standalone-bytecode-vm-no-gil並行性--nan-boxing--pyo3)
- [4. Python 双方向ゼロコピー相互運用プロトコル (Zero-Copy Interop)](#4-python-双方向ゼロコピー相互運用プロトコル-zero-copy-interop)
  - [4.1 Lazy View / Opaque Wrapper による $O(1)$ 型連携](#41-lazy-view--opaque-wrapper-による-o1-型連携)
  - [4.2 境界ラッパー (Boundary Guard) による現場復帰コンディション](#42-境界ラッパー-boundary-guard-による現場復帰コンディション)
  - [4.3 Python からの透過インポート (`sys.meta_path` / PyO3)](#43-python-からの透過インポート-sysmeta_path--pyo3)
- [5. ドメイン特化機能 (Domain Primitives)](#5-ドメイン特化機能-domain-primitives)
  - [5.1 S-OKF: ドキュメント同形性 (Document as S-Expression)](#51-s-okf-ドキュメント同形性-document-as-s-expression)
  - [5.2 パイプライン・スレッディングマクロ (|>>)](#52-パイプラインスレッディングマクロ-)
  - [5.3 記号推論 (miniKanren) 統合](#53-記号推論-minikanren-統合)
- [6. ブートストラップ連鎖と Kernel ILISP 仕様](#6-ブートストラップ連鎖と-kernel-ilisp-仕様)
  - [6.1 Kernel ILISP (最小ブートストラップ核) の定義](#61-kernel-ilisp-最小ブートストラップ核-の定義)
  - [6.2 3段階ブートストラップ手順と不動点検証](#62-3段階ブートストラップ手順と不動点検証)
- [7. ディレクトリ構成と自己完結ドキュメント体系 (`ilisp/docs/`)](#7-ディレクトリ構成と自己完結ドキュメント体系-ilispdocs)
- [8. 品質ゲート・テスト戦略](#8-品質ゲートテスト戦略)

---

## 0. 概要と基本方針 (Executive Summary)

本仕様書は、学術論文セキュリティ解析・OKFナレッジベース構築プラットフォームにおけるコア言語基盤として、**ILISP (Intelligence LISP)** を設計・定義するものである。

ILISP は、世界標準規格 **R7RS-small Scheme** を厳格な規範とし、次の 3 つの課題を抜本的に解決する：
1. **Python エコシステムとの摩擦ゼロ・ゼロコピー相互運用**: AI/NLP ライブラリを $O(1)$ コストでシームレスに直接呼び出す。
2. **C99 AOT トランスパイルによるネイティブ単一バイナリ**: 外部依存ゼロの C99 を出力し、`clang -O3` を介して LLVM 最適化の恩恵を享受する。
3. **Rust 製 Standalone Bytecode VM による極限の並列性能**: 将来のマルチコア並列処理・No-GIL 実行を担う NaN-Boxing バイトコード VM を提供する。

---

## 1. 言語哲学とアイデンティティ (Intelligence + IKE + AI + LISP)

```
        ┌────────────────────────────────────────────────────────┐
        │                 ILISP (Intelligence LISP)              │
        │   ~ Next-Gen Lisp for AI, Security & Document Science ~│
        └───────────────────────────┬────────────────────────────┘
                                    │
       ┌────────────────────────────┼────────────────────────────┐
       ▼                            ▼                            ▼
【 Intelligence 】              【 IKE 】                    【 AI / LISP 】
・脅威インテリジェンス          ・創設者アーキテクチャ哲学   ・S式・同形性・記号推論
・知識オントロジー (SKO)        ・極限のシンプルさと自作主義 ・Scope Sets 衛生的マクロ
・耐量子暗号・セキュリティ検証  ・セルフホスティング指向    ・R7RS Scheme 世界標準規格
```

- **Intelligence**: 論文から脅威情報・セキュリティ知見を抽出・構造化・推論する言語目的。
- **IKE**: 創設者の哲学である「車輪の原理を理解し、自己完結した高信頼基盤を創出する」精神。
- **AI**: LLM と記号推論（Symbolic AI / miniKanren）をシームレスに結合する AI ネイティブ構文。
- **LISP**: 半世紀以上の歴史を持つ同形性（Code is Data / Data is Code）の美学。

---

## 2. R7RS-small 言語仕様と処理系工学的精緻化

### 2.1 言語コアの最小直交性
ILISP は、2013年に策定された **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme)** を言語仕様のコアに採用する。
- 巨大で方言差の激しい Common Lisp と比較して、言語コアが小さく無駄がない。
- `define-library` による洗練されたモジュール境界が規格化されている。

### 2.2 Scope Sets アルゴリズムによる衛生的マクロとフェーズ分離
古典的な Kohlbecker のアルゴリズムや Syntax-case の複雑性を排し、Matthew Flatt (2016) によって確立された **Scope Sets アルゴリズム** をマクロ展開エンジンに採用する。
- **識別子のスコープ集合**: すべての識別子は導入元の「スコープの集合」を保持し、マクロ展開後も変数の捕捉（Capture）が論理的に発生しない。
- **フェーズ分離 (Phase Distinction)**:
  - コンパイル時フェーズ（Phase 1: Macro Expansion Time）での Python 任意副作用呼び出しを初期段階では遮断し、純粋 AST 変換に限定する。
  - これにより、マクロ展開の決定性とクロスコンパイル安全性を死守する。

### 2.3 ハイブリッド末尾呼出最適化 (Hybrid TCO)
Python ランタイムおよびネイティブ環境の特性に応じ、**ハイブリッド TCO 戦略** を採用する：
1. **自己末尾再帰（Self Tail Call）**: 同一関数内の末尾再帰を静的解析し、Python AST の `while True:` ループおよび代入に直接トランスパイル（スタック消費ゼロ・関数呼出オーバーヘッドゼロ）。
2. **相互末尾呼び出し（Mutual Tail Calls）**: 高階関数や異なる関数間の末尾呼び出しにおいてのみ、軽量トランポリン（タプル返却）を適用し、スタックオーバーフローを防止する。

### 2.4 階層的継続セマンティクス (Hierarchical call/cc)
ホスト環境の物理制約を鑑み、継続のサポートを階層化する：
- **Python バックエンド (Stage-0)**: 実用ユースケースの 95% を占める **「脱出継続（Escaping / One-shot Continuation）」** をサポート。Python ネイティブ例外機構によりスタック巻き戻しをゼロコストで実現。多重再突入時は `ContinuationsCanOnlyBeInvokedOnceError` を明示送出。
- **C99 AOT バックエンド (Stage-1)**: スタックフレーム複写または Cheney on the MTA（ヒープスタック法）により、完全な **Multishot 一級継続** をサポート。

---

## 3. 3本柱の実行バックエンド体系 (The Three Pillars of Execution)

```
                    ┌─────────────────────────┐
                    │  ILISP ソースコード      │
                    │  (R7RS-small + 独自拡張)│
                    └────────────┬────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
【1. Python AST Backend】  【2. C99 AOT Backend】   【3. Rust Bytecode VM】
  (初期〜現行開発)           (セルフホスティング)       (スタンドアロン超高速実行)
  ・Python とのゼロ摩擦相互    ・外部依存ゼロの単一バイ    ・NaN-Boxing 64bit 高速VM
    運用 (直接 import)          ナリ生成                 ・No-GIL マルチコア並列実行
  ・開発 DX / 対話型 REPL      ・Clang 経由で LLVM 最適化  ・PyO3 による Python ネイティブ
                               ・自己完結 ARC / コピー GC   Extension 提供
```

### 3.1 Backend A: Python AST トランスパイラ (Python Interop モード)
- ILISP の AST を Python 標準の `ast.AST` にコンパイルし、`compile(tree, filename, 'exec')` を通じて CPython 上で実行。
- 既存の Python パイプライン（`arxiv_okf_fetcher.py` や `manage.py`）からシームレスに部品として呼び出し可能。

### 3.2 Backend B: Native C99 AOT コンパイラ (Clang/LLVM 連携 & 自己完結 ARC)
- 動的型、Cons セル、環境フレームを標準 C99 コードにトランスパイル。
- **Clang 経由の実質 LLVM 最適化**: 生成された C99 コードを `clang -O3` でビルドすることで、自前で LLVM IR を記述することなく LLVM の最高峰最適化パス（インライン展開、定数伝播、SIMDベクトル化）を自動享受。
- **自己完結型 ARC（Automatic Reference Counting）**: 外部の Boehm GC（`libgc`）に依存せず、ランタイムヘッダ単体で完結する決定論的メモリ管理を採用。

### 3.3 Backend C: Rust Standalone Bytecode VM (No-GIL並行性 & NaN-Boxing & PyO3)
- スタンドアロン実行および極限の並列処理を担う第 3 の柱（将来拡張・フェーズ 2）。
- **NaN-Boxing**: 64ビット浮動小数点数の未使用領域にポインタやタグ値を詰め込む超高密度・高速メモリアーキテクチャ。
- **Fearless Concurrency**: Rust の所有権モデルにより、Python の GIL 制約を受けないマルチコア並列パイプラインを実現。
- **PyO3 連携**: Rust 製 VM を Python ネイティブ拡張（`.so`）としてビルド可能にし、Ruff や Polars と同等のパフォーマンスを提供。

---

## 4. Python 双方向ゼロコピー相互運用プロトコル (Zero-Copy Interop)

### 4.1 Lazy View / Opaque Wrapper による $O(1)$ 型連携
Python の `list` や `dict` を Scheme の Cons セルや Alist へ一括ディープコピーする $O(N)$ 処理を廃止し、**不透明ラッパー（Opaque Wrapper / Lazy View）** を採用する。
- Python オブジェクトをラップしたまま ILISP 側へ渡し、Scheme のベクタやマッププロトコルで $O(1)$ 参照。
- 明示的に `(py->list ...)` を呼んだ場合のみ連結リストに変換。

```scheme
(import (scheme base)
        (scheme write)
        (ilisp python))

;; Python モジュールのインポート
(import-python (arxiv Search)
               (pathlib Path))

(define (fetch-crypto-papers limit)
  (let ((search (py-call Search :query "cat:cs.CR AND post-quantum" :max_results limit)))
    ;; search.results (Python generator) を Lazy View のまま走査 (Zero-Copy)
    (py-for-each (lambda (paper)
                   (display (py-get paper 'title))
                   (newline))
                 (py-call search 'results))))
```

### 4.2 境界ラッパー (Boundary Guard) による現場復帰コンディション
Python の関数呼び出し時に例外が発生した場合でも、スタック巻き戻し前に「再試行クロージャ（Thunk）」を封入したコンディションオブジェクトを生成し、ILISP の `restart-case` へ引き渡す。

```scheme
(define (fetch-paper-resilient arxiv-id)
  (restart-case
      (py-call requests 'get (format "https://arxiv.org/abs/~a" arxiv-id))
    (wait-and-retry (delay-sec)
      :report "指定秒数待機してリトライ"
      (sleep delay-sec)
      (fetch-paper-resilient arxiv-id))
    (fallback-to-rss ()
      :report "RSSフィードからメタデータを補完取得"
      (fetch-rss-metadata arxiv-id))))
```

### 4.3 Python からの透過インポート (`sys.meta_path` / PyO3)
Python スクリプトから通常通り `.ilisp` ファイルを `import` 可能にする。

```python
# Python 側からの透過インポート
import ilisp.interop
import my_pipeline  # my_pipeline.ilisp が透過コンパイル・ロードされる

result = my_pipeline.harvest_papers(limit=10)
```

---

## 5. ドメイン特化機能 (Domain Primitives)

### 5.1 S-OKF: ドキュメント同形性 (Document as S-Expression)
Google OKF v0.2 の YAML フロントマターおよび Markdown 本文を S式ツリーとしてネイティブ表現する。

```scheme
(define-okf-paper "2403.12345"
  :frontmatter
  ((type . "security-paper")
   (title . "Zero-Trust Lattice Cryptography")
   (tags . (cryptography zero-trust))
   (provenance . ((origin . "arxiv.org") (date . "2026-10-04"))))
  :body
  ((h1 "1. 概要")
   (p "ゼロトラストネットワークにおける耐量子格子暗号の評価を行う。")))
```

### 5.2 パイプライン・スレッディングマクロ (`|>>`)
データの入力から加工、OKF変換、階層集計までを直感的なパイプラインとして結合。

### 5.3 記号推論 (miniKanren) 統合
[DSN-29](DSN-29-python_lisp_integrated_architecture_specification.md) の `logic.py` を基盤とし、MITRE ATT&CK や STRIDE 脅威モデルのルールベース推論をファーストクラスで実行。

---

## 6. ブートストラップ連鎖と Kernel ILISP 仕様

### 6.1 Kernel ILISP (最小ブートストラップ核) の定義
セルフホスティング（Stage-1）のコンパイラ自身を記述するため、複雑なマクロや高度なデータ型に依存しない **最小仕様「Kernel ILISP」** を先行凍結する：
- **構文要素 (6大基本式)**:
  1. 変数参照 (`x`)
  2. 定数リテラル (`quote`, 整数, 文字列, シンボル, 真偽値)
  3. 手続き定義 (`lambda`)
  4. 条件分岐 (`if`)
  5. 代入 (`set!`)
  6. 順序実行 (`begin`)
- **コアプリミティブ**: `cons`, `car`, `cdr`, `pair?`, `symbol?`, `string?`, `eq?`, `+`, `-`, `<`, `write-char`, `read-char`
- **制御構造**: 自己末尾再帰ループ（ループ構文はすべてこれに脱糖）

### 6.2 3段階ブートストラップ手順と不動点検証

```
[ compiler.ilisp (Kernel ILISP) ] ──( Stage-0: Python compiler.py )──▶ [ ilisp_stage1.c ]
                                                                             │ (gcc/clang -O3)
                                                                             ▼
                                                                      [ ilisp-stage1 (bin) ]
                                                                             │
[ compiler.ilisp (Kernel ILISP) ] ──( Stage-1: ilisp-stage1 )────────▶ [ ilisp_stage2.c ]
                                                                             │ (gcc/clang -O3)
                                                                             ▼
                                                                      [ ilisp-stage2 (bin) ]
                                                                             │
                               [ 不動点検証: diff ilisp_stage1.c ilisp_stage2.c == 0 ]
```

1. **Stage-0 (Python Host)**: Pure Python の最小コンパイラで `compiler.ilisp` を C99 コード `ilisp_stage1.c` にトランスパイル。
2. **Stage-1 (ILISP-in-ILISP)**: `ilisp-stage1` 実行ファイルを用いて、自身（`compiler.ilisp`）を再コンパイルし `ilisp_stage2.c` を出力。
3. **Stage-2 (Fixed-Point Verification)**: `diff ilisp_stage1.c ilisp_stage2.c` が差分ゼロ（不動点到達）であることを機械検証。

---

## 7. ディレクトリ構成と自己完結ドキュメント体系 (`ilisp/docs/`)

```
ilisp/
├── docs/                          # ★ ILISP 自己完結ドキュメント体系 ★
│   ├── README.md                  # ILISP 概要・クイックスタート・3本柱理念
│   ├── SPEC_R7RS.md               # R7RS-small 準拠マトリクス・Scope Sets・TCO仕様
│   ├── PYTHON_INTEROP.md          # Python ゼロコピー相互運用仕様
│   ├── MACROS_AND_CONDITIONS.md   # Scope Sets マクロ & 現場復帰コンディション詳細
│   └── BOOTSTRAP.md               # Kernel ILISP 仕様 & 3段階ブートストラップ連鎖
├── compiler/                      # コンパイラコア (Reader, Lexer, AST, Scope Sets)
├── backend/
│   ├── py_codegen/                # Python AST バックエンド (Zero-Copy Lazy View)
│   └── c_codegen/                 # Native C99 AOT バックエンド (Clang/LLVM & ARC)
├── vm/                            # Rust Standalone Bytecode VM (Phase 2)
├── runtime/                       # ランタイムコア (Hybrid TCO, Environment, Primitives)
├── stdlib/                        # (scheme base), (ilisp ...) 標準ライブラリ
├── tests/                         # ILISP 独自テストスイート
└── repl.py                        # 対話型 REPL エントリーポイント
```

---

## 8. 品質ゲート・テスト戦略

本仕様書に基づくすべての実装は、リポジトリの品質基準（DoD）を満たす必要がある：
1. **R7RS 適合性テスト**: 標準 R7RS テストスイート（テストケース 200+ 件）の順次合格。
2. **Zero-Copy Python Interop テスト**: メモリコピーを伴わない Python イテレータ走査の計算量検証。
3. **ブートストラップ不動点テスト**: `make test-bootstrap` により、ステージ間コンパイル結果の差分ゼロを機械的に監査。
4. **トリプル品質ゲート**: `make check_format`, `make static_analysis`, `make test` の 100% PASS。

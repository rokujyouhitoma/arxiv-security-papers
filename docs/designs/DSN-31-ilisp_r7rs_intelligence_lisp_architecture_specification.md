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
  - [DSN-32 (AILisp Agent Lisp Architecture Specification)](DSN-32-ailisp_agent_lisp_architecture_specification.md)
  - [DSN-33 (ULisp Underlying x86-64 Native AOT Compiler Architecture Specification)](DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **【主査・報告】 IT Specialist (Programming Languages & Compilers / PLC) / Systems Architect (SA)**
- **【共同主査】 Project Manager (PM) / Software Development (SWD) / Software Quality Assurance Specialist (QA)**
- **【参画・協調】 16 大専門エージェント全員 (PM, SEC, SA, QA, DBA, NET, NLP, STR, SM, EMB, AUD, DES, EDU, SWD, APS, PLC)**

---

## 体系目次

- [0. 概要と基本方針 (Executive Summary)](#0-概要と基本方針-executive-summary)
- [1. 言語哲学とアイデンティティ (Intelligence + IKE + AI + LISP)](#1-言語哲学とアイデンティティ-intelligence--ike--ai--lisp)
- [2. R7RS-small 言語仕様と処理系工学的精緻化](#2-r7rs-small-言語仕様と処理系工学的精緻化)
  - [2.1 言語コアの最小直交性](#21-言語コアの最小直交性)
  - [2.2 衛生的マクロの段階的導入 (Phase 1 構文置換 → Phase 2 Scope Sets)](#22-衛生的マクロの段階的導入-phase-1-構文置換--phase-2-scope-sets)
  - [2.3 ハイブリッド末尾呼出最適化 (Hybrid TCO)](#23-ハイブリッド末尾呼出最適化-hybrid-tco)
  - [2.4 階層的継続セマンティクス (脱出継続・再突入 dynamic-wind ガード)](#24-階層的継続セマンティクス-脱出継続再突入-dynamic-wind-ガード)
  - [2.5 レキシカル環境と代入のボックス化戦略 (Cell 変数昇格)](#25-レキシカル環境と代入のボックス化戦略-cell-変数昇格)
  - [2.6 手書き再帰下降リーダーと構文解析厳密化](#26-手書き再帰下降リーダーと構文解析厳密化)
  - [2.7 完全数値タワーと厳密書式出力 (Fractions, SchemeComplex, 述語整合)](#27-完全数値タワーと厳密書式出力-fractions-schemecomplex-述語整合)
- [3. 3本柱の実行バックエンド体系 (The Three Pillars of Execution)](#3-3本柱の実行バックエンド体系-the-three-pillars-of-execution)
  - [3.1 Backend A: Python AST トランスパイラ (Python Interop モード)](#31-backend-a-python-ast-トランスパイラ-python-interop-モード)
  - [3.2 Backend B: Native C99 AOT コンパイラ (Clang/LLVM 連携 & 自己完結 ARC)](#32-backend-b-native-c99-aot-コンパイラ-clangllvm-連携--自己完結-arc)
  - [3.3 Backend C: Rust Standalone Bytecode VM (No-GIL並行性 & NaN-Boxing & PyO3)](#33-backend-c-rust-standalone-bytecode-vm-no-gil並行性--nan-boxing--pyo3)
  - [3.4 3段階開発ロードマップ (Phased Implementation Milestones)](#34-3段階開発ロードマップ-phased-implementation-milestones)
- [4. Python 双方向ゼロコピー相互運用プロトコル (Zero-Copy Interop)](#4-python-双方向ゼロコピー相互運用プロトコル-zero-copy-interop)
  - [4.1 Lazy View / SequenceView による $O(1)$ リスト相互運用プロトコル](#41-lazy-view--sequenceview-による-o1-リスト相互運用プロトコル)
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

本仕様書は、学術論文セキュリティ解析・OKFナレッジベース構築プラットフォームにおけるコア言語基盤として、**ILISP (Intelligence LISP / Infrastructure LISP)** を設計・定義するものである。

ILISP は、世界標準規格 **R7RS-small Scheme** を厳格な規範とし、上位のAIエージェント安全制御レイヤー **ALisp (Agent Lisp / DSN-32)** と融合して **AILisp (AI Lisp)** の強固な基盤（Infrastructure）を形成するとともに、次の 4 つの課題を抜本的に解決する：
1. **AILisp の基盤実行レイヤー (Infrastructure Engine)**: ALisp から委譲される検証済み AST を最高速度で実行し、`with-fuel` や `with-caps` に呼応する Managed Port・実行時サンドボックス基盤を提供する。
2. **Python エコシステムとの摩擦ゼロ・ゼロコピー相互運用**: AI/NLP ライブラリを $O(1)$ コストでシームレスに直接呼び出す。
3. **C99 AOT トランスパイルによるネイティブ単一バイナリ**: 外部依存ゼロの C99 を出力し、`clang -O3` を介して LLVM 最適化の恩恵を享受する。
4. **Rust 製 Standalone Bytecode VM による極限の並列性能**: 将来のマルチコア並列処理・No-GIL 実行を担う NaN-Boxing バイトコード VM を提供する。

---

## 1. 言語哲学とアイデンティティ (Intelligence + Infrastructure + IKE + AI + LISP)

```
        ┌────────────────────────────────────────────────────────┐
        │        ILISP (Intelligence & Infrastructure LISP)      │
        │   ~ Next-Gen Lisp for AI, Security & Document Science ~│
        └───────────────────────────┬────────────────────────────┘
                                    │
       ┌───────────────┬────────────┴───────────┬───────────────┐
       ▼               ▼                        ▼               ▼
【 Intelligence 】 【 Infrastructure 】     【 IKE 】       【 AI / LISP 】
・脅威インテリ     ・AILisp の強固な実行基盤   ・創設者哲学     ・S式・同図像性・記号推論
・知識オントロジー ・Managed Port / FFI 境界   ・自作主義       ・Scope Sets 衛生的マクロ
・耐量子暗号検証   ・決定論的高速ランタイム     ・セルフホスト   ・R7RS Scheme 世界標準規格
```

- **Intelligence / Infrastructure**: 論文から脅威知見を抽出・推論する言語目的であると同時に、次世代 AI コーディングエージェント実行環境 **AILisp** の揺るぎない基盤（Infrastructure）を担う。
- **IKE**: 創設者の哲学である「車輪の原理を理解し、自己完結した高信頼基盤を創出する」精神。
- **AI**: LLM と記号推論（Symbolic AI / miniKanren）をシームレスに結合し、上位 ALisp の自律実行を支える。
- **LISP**: 半世紀以上の歴史を持つ同形性（Code is Data / Data is Code）の美学。

---

## 2. R7RS-small 言語仕様と処理系工学的精緻化

### 2.1 言語コアの最小直交性
ILISP は、2013年に策定された **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme)** を言語仕様のコアに採用する。
- 巨大で方言差の激しい Common Lisp と比較して、言語コアが小さく無駄がない。
- `define-library` による洗練されたモジュール境界が規格化されている。

### 2.2 衛生的マクロの段階的導入 (Phase 1 構文置換 → Phase 2 Scope Sets)
マクロ展開器の実装複雑性によるブートストラップの遅延を防ぐため、マクロ機能は以下の 2 段階で導入する：
1. **Phase 1 (ブートストラップ期・Kernel ILISP)**:
   - 原始的構文マクロ（`define-macro`）およびパターンマッチングによる基本形 `syntax-rules` を純粋 Python で実装。
   - コンパイラや標準ライブラリの基本制御構文（`when`, `unless`, `cond`, `and`, `or`, `let*`, `letrec` 等）を自前で展開可能にする。
2. **Phase 2 (成熟期・完全 R7RS 準拠)**:
   - 古典的な Kohlbecker のアルゴリズムや Syntax-case の複雑性を排し、Matthew Flatt (2016) によって確立された **Scope Sets アルゴリズム** をマクロ展開エンジンに採用。
   - **識別子のスコープ集合**: すべての識別子は導入元の「スコープの集合」を保持し、マクロ展開後も変数の捕捉（Capture）が論理的に発生しない。
   - **フェーズ分離 (Phase Distinction)**: コンパイル時フェーズ（Macro Expansion Time）での Python 任意副作用呼び出しを遮断し、純粋 AST 変換に限定することで決定性とクロスコンパイル安全性を死守する。

### 2.3 ハイブリッド末尾呼出最適化 (Hybrid TCO)
Python ランタイムおよびネイティブ環境の特性に応じ、**ハイブリッド TCO 戦略** を採用する：
1. **自己末尾再帰（Self Tail Call）**: 同一関数内の末尾再帰を静的解析し、Python AST の `while True:` ループおよび代入に直接トランスパイル（スタック消費ゼロ・関数呼出オーバーヘッドゼロ）。
2. **相互末尾呼び出し（Mutual Tail Calls）**: 高階関数や異なる関数間の末尾呼び出しにおいてのみ、軽量トランポリン（タプル返却）を適用し、スタックオーバーフローを防止する。

### 2.4 階層的継続セマンティクス (脱出継続・再突入 dynamic-wind ガード)
ホスト環境の物理制約を鑑み、継続のサポートを階層化する：
- **Python バックエンド (Stage-0 / Phase 1〜2)**:
  - 実用ユースケースの 95%（大域脱出・例外処理・早期リターン）を占める **「脱出継続（Escaping / One-shot Continuation）」** を高効率サポート。
  - Python ネイティブ例外機構によりスタック巻き戻しをゼロコストで実現。
  - **動的巻き戻しと再突入順序保証 (`dynamic-wind`)**:
    - `Continuation` オブジェクト生成時に、現在の `wind_frame`（実行中の `dynamic-wind` スタックフレーム）をスナップショット記録。
    - 継続がその生成スコープ（extent）から脱出した後、外部スコープから再突入呼出（Re-entry invocation）された場合でも、記録された `wind_frame` に基づき、巻き戻し Thunk（`before`）の順序通りの再実行、更新式評価、およびクリーンアップ Thunk（`after`）の安全な連鎖を保証。
- **C99 AOT / Rust VM バックエンド (Stage-1〜2 / Phase 2〜3)**:
  - スタックフレーム複写または Cheney on the MTA（ヒープスタック法）により、完全な **Multishot 一級継続** をサポート。

### 2.5 レキシカル環境と代入のボックス化戦略 (Cell 変数昇格)
Scheme のレキシカルスコープと `set!`（破壊的代入）を Python AST 上で自然かつ安全に再現するため、**Cell（ボックス化）戦略** を採用する：
- **静的代入解析（Mutated Variable Analysis）**: コンパイル時に各スコープで定義された識別子のうち、スコープ内外から `set!` で変更される変数のみを静的に検出する。
- **Cell オブジェクトへの昇格**:
  - 不変な変数（大多数）は、通常の Python ローカル変数として直接参照（オーバーヘッドゼロ）。
  - `set!` 対象となる変更可能変数のみを単一要素のミュータブルコンテナ `Cell(value)` に昇格させる。
- **`nonlocal` 構文エラーの根本排除**: Python の `nonlocal` 制約（入れ子スコープでの重複定義やシャドーイングによる SyntaxError）を完全に回避し、Scheme の自由な変異セマンティクスを忠実に保証する。

### 2.6 手書き再帰下降リーダーと構文解析厳密化
外部構文解析ジェネレータ（Lark, PLY, ANTLR 等）への依存を排除し、**極小の手書き再帰下降リーダー（Tokenizer + Reader、約300行）** を採用する：
- **正確なソースマップ位置追跡**: すべての S式ノード（Pair, Symbol, Literal）にファイル名、行番号、列番号（`SourceLocation(file, line, col)`）をメタデータとして保持。コンパイルエラーや実行時エラーで正確なスタックトレースを提示。
- **リーダーマクロの軽量拡張**: クォート（`'`）、準クォート（`\``）、アンクォート（`,`）、アンクォート・スプライシング（`,@`）、S式コメント（`#;`）を決定論的に解析。
- **孤立ドット記法（Standalone Dot）の構文検証**:
  - Scheme R7RS において、単独の `.` は識別子シンボルではなくドットペア構文専用のトークンであるため、孤立した `.` をアトムとして誤読せず、厳密に `LispSyntaxError`（`read-error?` 適合）として弾く構文検証機構を内蔵。
- **Datum Comment (`#;`) の厳密処理**:
  - コメント対象となる直後の完全な 1 Datum を正確に読み飛ばし、後続の S 式ストリームの整合性を死守。

### 2.7 完全数値タワーと厳密書式出力 (Fractions, SchemeComplex, 述語整合)
R7RS-small 第6.2節「Numbers」の厳格な仕様に完全適合するため、数値タワーを以下のように工学的に精緻化する：
- **有理数（Exact Fractions）の完全サポート**:
  - `1/2`、`-3/4`、`10/2` などの分数表記リテラルを Python 標準 `fractions.Fraction` としてパース・保持。
  - 約分・約数・公倍数演算（`gcd`, `lcm`）および商余剰多値（`exact-integer-sqrt`, `floor/`, `truncate/` 等）を正確に計算。
- **複素数モデル (`SchemeComplex`) の厳密化**:
  - 浮動小数点誤差を伴う Python ネイティブ `complex` だけでなく、実部・虚部をそれぞれ任意精度整数・有理数・実数として保持可能な `SchemeComplex(real, imag, real_val, imag_val, exact_imag)` を導入。
  - `write` / `display` において、`0.5+3/4i`、`2+0i`、`+inf.0-inf.0i` 等の厳密表現文字列化を忠実に出力。
- **数学的型述語の仕様厳密準拠**:
  - R7RS 6.2.5 仕様に基づき、複素数であっても「虚部が厳密な 0（`exact_imag == True` かつ `imag == 0.0`）」である場合のみ `real?` を真とし、不厳密な虚部 `+0.0i` を持つ複素数は `real?` を偽とする厳格な述語ディスパッチを実現。

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

### 3.4 3段階開発ロードマップ (Phased Implementation Milestones)
ILISP の実装は、外部依存と不確実性を最小化するため、明確に定義された 3 段階のマイルストーンに沿って進める：

| フェーズ | 名称 | 目的・主眼 | 主要コンポーネント | 依存関係 |
| :--- | :--- | :--- | :--- | :--- |
| **Phase 1** | **Kernel ILISP 最小構成**<br>*(現行マイルストーン)* | 外部依存ゼロで即座に動作するコア言語基盤の確立 | 手書き Reader (S式パース)<br>最小 AST<br>Tree-walk 評価器<br>基本型 & プリミティブ (23個)<br>対話型 REPL<br>基本 Python interop | **純粋 Python のみ**<br>(標準ライブラリ以外ゼロ依存) |
| **Phase 2** | **Advanced Macro & Transpiler** | 実用エコシステム統合とネイティブコード生成 | Scope Sets 衛生的マクロ展開器<br>Python AST トランスパイラ (Backend A)<br>C99 AOT トランスパイラ (Backend B)<br>Clang/LLVM 連携<br>S-OKF パイプライン連携 | Clang / LLVM (AOT時のみ) |
| **Phase 3** | **Extreme Performance & VM** | 超高速実行・並行処理と完全セルフホスティング | Rust Standalone Bytecode VM (Backend C)<br>NaN-Boxing 値表現<br>No-GIL マルチコア並行エンジン<br>PyO3 バインディング<br>完全セルフホスティング検証 | Rust toolchain / cargo (VM時のみ) |

---

## 4. Python 双方向ゼロコピー相互運用プロトコル (Zero-Copy Interop)

### 4.1 Lazy View / SequenceView による $O(1)$ リスト相互運用プロトコル
Scheme 固有の連結リスト（Cons セル）と Python の動的配列（`list`）の間の変換コストを最小化するため、以下のハイブリッドデータ構造を採用する：
- **基本リスト表現**: ILISP 内部では伝統的な `Cons(car, cdr)` によるペア構造を第一級市民とする。
- **`SequenceView` (不透明ラッパー)**:
  - Python の `list` や `tuple` をラップし、インデックスオフセットを保持する軽量イミュータブルビュー `SequenceView(seq, offset=0)` を提供。
  - `(car view)` は `seq[offset]` を $O(1)$ で返却。
  - `(cdr view)` は `SequenceView(seq, offset+1)` を $O(1)$（スライス複写なし）で返却。
  - これにより、数万件の arXiv 論文リストを Scheme 関数に渡す際、一括ディープコピー（$O(N)$）を完全回避。
- **Python 境界での自動アンラップ**: Python 側の関数に渡される際は、必要に応じて透過的に Python ネイティブコレクションへとアンラップされる。

```scheme
(import (scheme base)
        (scheme write)
        (ilisp python))

;; Python モジュールのインポート (モジュール・クラス・関数・エイリアス対応)
(import-python (arxiv Search)
               (pathlib Path)
               (torch :as th)
               (transformers (AutoTokenizer :as Tok)))
;; 高次マクロ展開器により以下へ安全に脱糖 (Desugaring):
;;   (define Search (py-get (py-import 'arxiv) 'Search))
;;   (define Path (py-get (py-import 'pathlib) 'Path))
;;   (define th (py-import 'torch))
;;   (define Tok (py-get (py-import 'transformers) 'AutoTokenizer))

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

ILISP は単一リポジトリ内で完結するよう、以下のディレクトリ構成に従う：

```
ilisp/
├── docs/                          # ★ ILISP 自己完結ドキュメント体系 ★
│   ├── README.md                  # ILISP 概要・クイックスタート・3本柱理念・テスト実行ガイド
│   ├── SPEC_R7RS.md               # R7RS-small 準拠マトリクス (全203機能) & chibi 100% 検証詳報
│   ├── PYTHON_INTEROP.md          # Python ゼロコピー相互運用・SequenceView・双方向呼出仕様
│   ├── MACROS_AND_CONDITIONS.md   # Scope Sets マクロ & 現場復帰コンディション & テストハーネス仕様
│   └── BOOTSTRAP.md               # Kernel ILISP 仕様 & 3段階ブートストラップ連鎖 & 不動点検証
├── reader.py                      # 手書き再帰下降 Reader (SourceLocation, リーダーマクロ, 構文検証)
├── types.py                       # コア型体系 (Cons, Symbol, Vector, Bytevector, SchemeComplex, Record)
├── numbers.py                     # 完全数値タワー (Exact Fraction, Complex, 除算・丸め・超越関数)
├── port.py                        # 入出力ポート抽象化 (StringPort, FilePort, バイナリ, 厳密書式出力)
├── char.py                        # 文字操作・Unicode カテゴリ・大文字小文字変換
├── syntax.py                      # Scope Sets 衛生的マクロ展開器 (syntax-rules, pattern-match, ellipsis)
├── env.py                         # レキシカル環境・フレーム探索・ビルトイン束縛 (Primitive Procedures)
├── evaluator.py                   # 評価エンジン・ハイブリッド TCO・階層的継続 (call/cc, dynamic-wind)
├── module.py                      # R7RS モジュールシステム (define-library, import, export, rename)
├── repl.py                        # 対話型 REPL エントリーポイント (履歴, 複数行入力, 診断)
├── backend/
│   ├── py_codegen/                # Python AST バックエンド (Zero-Copy Lazy View)
│   └── c_codegen/                 # Native C99 AOT バックエンド (Clang/LLVM & 自己完結 ARC)
├── stdlib/                        # R7RS 標準ライブラリ群 (.ilisp)
│   ├── base.ilisp                 # (scheme base) コア構文マクロ・高階関数・ユーティリティ
│   ├── write.ilisp                # (scheme write) display, write, write-shared
│   ├── read.ilisp                 # (scheme read) read 手続き
│   ├── cxr.ilisp                  # (scheme cxr) caar〜cddddr (24個の深層アクセサ)
│   ├── case_lambda.ilisp          # (scheme case-lambda) 多重アリティディスパッチ
│   ├── char.ilisp                 # (scheme char) 文字分類・大文字小文字比較
│   ├── complex.ilisp              # (scheme complex) 複素数操作
│   ├── inexact.ilisp              # (scheme inexact) 三角関数・指数対数・平方根
│   ├── lazy.ilisp                 # (scheme lazy) delay, force, delay-force, make-promise
│   ├── process_context.ilisp      # (scheme process-context) コマンドライン引数・環境変数
│   ├── time.ilisp                 # (scheme time) 現在時刻・単調クロック jiffy
│   ├── eval.ilisp                 # (scheme eval) 動的評価 eval, environment
│   └── repl.ilisp                 # (scheme repl) 対話環境 interaction-environment
├── tests/                         # R7RS 標準適合性テスト群
│   ├── r7rs_tests.scm             # chibi-scheme 原本 R7RS テストスイート (Alex Shinn, 3-Clause BSD)
│   └── test_harness.scm           # ILISP 独自テスト実行ハーネス (Project ILISP Authors, MIT License)
└── __init__.py                    # パッケージ初期化 & パブリック Python API エクスポート
```

---

## 8. 品質ゲート・テスト戦略

本仕様書に基づくすべての実装は、リポジトリの品質基準（DoD）を満たす必要がある：
1. **chibi-scheme 公式 R7RS 適合性テストスイート（100% 完全合格の永続担保）**:
   - `ilisp/tests/r7rs_tests.scm` にて提供される公式 R7RS-small テストスイート（全 1,233 項目）に対し、**100% 完全合格（1,233 PASS / 0 FAIL / 0 ERROR）** を達成し、リグレッションをゼロ許容。
   - **知的財産・ライセンス完全分離**: 上流由来のテスト本体（`r7rs_tests.scm`, 3-Clause BSD License）と、弊社オリジナルの独立テスト実行ハーネス（`ilisp/tests/test_harness.scm`, MIT License）を別ファイルとして物理的に分離・独立管理。
   - **失敗検知・自動診断レポート機構**: 万一の FAIL / ERROR 発生時には、`*test-failure-log*` より評価式・期待値・実際値・例外スタックを整形出力し、CI で即座に検出・特定。
   - **分離整合性検証**: CI において原本 `r7rs_tests.scm` に独自ハーネスが含まれていないこと、および `test_harness.scm` が MIT License ヘッダを保持していることを自動監査。
2. **回帰テストスイートの全数合格**:
   - `tests/ilisp/` 配下の全単体・統合テスト（372 件）の 100% PASS を常時維持（`pytest tests/ilisp -q` で約12秒で全件通過）。
3. **Zero-Copy Python Interop テスト**:
   - メモリコピーを伴わない Python イテレータ走査の計算量検証（`SequenceView` による $O(1)$ スライス操作）。
4. **ブートストラップ不動点テスト**:
   - `make test-bootstrap` により、ステージ間コンパイル結果の差分ゼロ（不動点到達）を機械的に監査。
5. **トリプル品質ゲートの完全準拠**:
   - 静的解析: `flake8 ilisp tests/ilisp` (エラー 0 件)
   - 型検査: `mypy --strict ilisp` (エラー 0 件)
   - コード規約: `make check_format` (Black / isort 差分 0 件)
   - 自動テスト: `pytest` (全件合格)

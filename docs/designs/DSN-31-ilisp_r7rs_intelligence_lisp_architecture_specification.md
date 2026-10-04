# [DSN-31] ILISP (Intelligence LISP) R7RS コアアーキテクチャ設計仕様書
## 〜 R7RS-small Scheme準拠・Python双方向相互運用・ネイティブC-AOTデュアルバックエンド・現場復帰型コンディション・3段階セルフホスティングブートストラップ連鎖 〜

- **文書番号**: `DSN-31`
- **文書ステータス**: `APPROVED`
- **対象サブシステム**:
  - `ilisp/` (ILISP 言語処理系基盤)
  - `ilisp/compiler/` (S式 Reader, Tokenizer, AST, Macro Expander)
  - `ilisp/backend/py_codegen/` (Python AST コード生成器 / Python Interop)
  - `ilisp/backend/c_codegen/` (Native C99 AOT コード生成器 / gcc・clang 連携)
  - `ilisp/runtime/` (TCO トランポリン, 環境 Environment, プリミティブ)
  - `ilisp/stdlib/` (R7RS 標準ライブラリ & ILISP 拡張モジュール)
  - `ilisp/docs/` (ILISP 言語固有ドキュメント体系)
- **関連設計書**:
  - [DSN-01 (High-Level Architecture)](DSN-01-high_level_design.md)
  - [DSN-24 (Unified Management CLI & Database Shell)](DSN-24-unified_management_cli_and_interactive_database_shell.md)
  - [DSN-25 (Pure-Python Packrat PEG Parser Engine & Bootstrap)](DSN-25-pure_python_packrat_peg_parser_engine.md)
  - [DSN-29 (Python-LISP Integrated Architecture Specification - pylisp)](DSN-29-python_lisp_integrated_architecture_specification.md)
- **【主査・報告】 Systems Architect (SA) / Software Development (SWD)**
- **【共同主査】 Project Manager (PM) / Information Security Specialist (SEC) / Software Quality Assurance Specialist (QA)**
- **【参画・協調】 15 大専門エージェント全員 (PM, SEC, SA, QA, DBA, NET, NLP, STR, SM, EMB, AUD, DES, EDU, SWD, APS)**

---

## 体系目次

- [0. 概要と基本方針 (Executive Summary)](#0-概要と基本方針-executive-summary)
- [1. 言語哲学とアイデンティティ (Intelligence + IKE + AI + LISP)](#1-言語哲学とアイデンティティ-intelligence--ike--ai--lisp)
- [2. R7RS-small 仕様準拠アーキテクチャ](#2-r7rs-small-仕様準拠アーキテクチャ)
  - [2.1 言語コアの最小直交性と安全性](#21-言語コアの最小直交性と安全性)
  - [2.2 衛生的マクロ (syntax-rules)](#22-衛生的マクロ-syntax-rules)
  - [2.3 末尾呼び出し最適化 (TCO) と継続 (call/cc)](#23-末尾呼び出し最適化-tco-と継続-callcc)
- [3. デュアル・コンパイル・バックエンド (Dual Compilation Backends)](#3-デュアルコンパイルバックエンド-dual-compilation-backends)
  - [3.1 Backend A: Python AST トランスパイラ (Python Interop モード)](#31-backend-a-python-ast-トランスパイラ-python-interop-モード)
  - [3.2 Backend B: Native C99 AOT コンパイラ (Chicken Scheme / Nim 方式)](#32-backend-b-native-c99-aot-コンパイラ-chicken-scheme--nim-方式)
- [4. Python 双方向相互運用プロトコル (Zero-Friction Interop)](#4-python-双方向相互運用プロトコル-zero-friction-interop)
  - [4.1 ILISP から Python ライブラリの直接呼出](#41-ilisp-から-python-ライブラリの直接呼出)
  - [4.2 Python から ILISP モジュールの透過インポート](#42-python-から-ilisp-モジュールの透過インポート)
- [5. 現場復帰型コンディションシステム (Conditions & Restarts)](#5-現場復帰型コンディションシステム-conditions--restarts)
- [6. ドメイン特化機能 (Domain Primitives)](#6-ドメイン特化機能-domain-primitives)
  - [6.1 S-OKF: ドキュメント同形性 (Document as S-Expression)](#61-s-okf-ドキュメント同形性-document-as-s-expression)
  - [6.2 パイプライン・スレッディングマクロ (|>>)](#62-パイプラインスレッディングマクロ-)
  - [6.3 記号推論 (miniKanren) 統合](#63-記号推論-minikanren-統合)
- [7. 3段階セルフホスティング・ブートストラップ連鎖](#7-3段階セルフホスティングブートストラップ連鎖)
  - [7.1 Stage-0: Python ホスト実装](#71-stage-0-python-ホスト実装)
  - [7.2 Stage-1: ILISP-in-ILISP コンパイラ](#72-stage-1-ilisp-in-ilisp-コンパイラ)
  - [7.3 Stage-2: 不動点検証 (Fixed-Point Verification)](#73-stage-2-不動点検証-fixed-point-verification)
- [8. ディレクトリ構成と自己完結ドキュメント体系 (`ilisp/docs/`)](#8-ディレクトリ構成と自己完結ドキュメント体系-ilispdocs)
- [9. 品質ゲート・テスト戦略](#9-品質ゲートテスト戦略)

---

## 0. 概要と基本方針 (Executive Summary)

本仕様書は、学術論文セキュリティ解析・OKFナレッジベース構築プラットフォームにおけるコア言語基盤として、**ILISP (Intelligence LISP)** を設計・定義するものである。

現在 Python で記述されているパイプラインは、NLP/AIライブラリの利便性を享受する一方で、PDFバイナリ解析（CMap/フォントデコード）のCPU負荷、GIL（Global Interpreter Lock）によるスレッド並列制約、および例外発生時のリカバリ柔軟性に課題を抱えている。

ILISP は、世界標準規格 **R7RS-small Scheme** を厳格な規範とし、**「Pythonエコシステムとの摩擦ゼロ相互運用」** と **「C言語コード生成によるネイティブAOT単一バイナリ高速実行」** を両立する。さらに、本リポジトリの先例（DSN-25 PEGパーサ自己ホスティング）を継承し、**将来の完全自己完結セルフホスティング（Bootstrap Chain）** を前提としたアーキテクチャを確立する。

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
・知識オントロジー (SKO)        ・極限のシンプルさと自作主義 ・衛生的マクロ (syntax-rules)
・耐量子暗号・セキュリティ検証  ・セルフホスティング指向    ・R7RS Scheme 世界標準規格
```

- **Intelligence**: 論文から脅威情報・セキュリティ知見を抽出・構造化・推論する言語目的。
- **IKE**: 創設者の哲学である「車輪の原理を理解し、自己完結した高信頼基盤を創出する」精神。
- **AI**: LLM と記号推論（Symbolic AI / miniKanren）をシームレスに結合する AI ネイティブ構文。
- **LISP**: 半世紀以上の歴史を持つ同形性（Code is Data / Data is Code）の美学。

---

## 2. R7RS-small 仕様準拠アーキテクチャ

### 2.1 言語コアの最小直交性と安全性
ILISP は、2013年に策定された **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme)** を言語仕様のコアに採用する。
- 巨大で方言差の激しい Common Lisp と比較して、言語コアが小さく無駄がない。
- `define-library` による洗練されたモジュール境界が規格化されている。

### 2.2 衛生的マクロ (syntax-rules)
Common Lisp の `defmacro` で頻発する「変数捕捉（Variable Capture）」事故を原理的に排除するため、パターンマッチングベースの衛生的マクロ（Hygienic Macro: `define-syntax`, `syntax-rules`）を標準搭載する。

```scheme
;; パイプライン・スレッディングマクロ (|>>) の衛生的定義例
(define-syntax |>>
  (syntax-rules ()
    ((|>> x) x)
    ((|>> x (f arg ...)) (f x arg ...))
    ((|>> x f) (f x))
    ((|>> x (f arg ...) rest ...)
     (|>> (f x arg ...) rest ...))
    ((|>> x f rest ...)
     (|>> (f x) rest ...))))
```

### 2.3 末尾呼び出し最適化 (TCO) と継続 (call/cc)
- **TCO (Tail Call Optimization)**: 末尾位置の関数呼び出しはスタックフレームを消費せず、ループと等価な $O(1)$ メモリ空間で実行されることを保証する。
- **ファーストクラスの継続 (`call/cc`)**: コルーチン、非同期タスクの中断・再開、ジェネレータ制御を言語レベルで完全にサポートする。

---

## 3. デュアル・コンパイル・バックエンド (Dual Compilation Backends)

```
                            ┌─────────────────────┐
                            │  ILISP S-Expression │
                            └──────────┬──────────┘
                                       │ (Macro Expansion & Desugaring)
                                       ▼
                            ┌─────────────────────┐
                            │  Core IR (CPS/ANF)  │
                            └────┬───────────┬────┘
                                 │           │
            ┌────────────────────┘           └────────────────────┐
            ▼                                                     ▼
【 Backend A: Python AST 】                           【 Backend B: Native C99 AOT 】
 (ilisp.backend.py_codegen)                            (ilisp.backend.c_codegen)
 ─────────────────────────                             ─────────────────────────
 ・Python `ast.AST` ノード生成                         ・ポータブルな標準 C99 コード出力
 ・CPython 実行空間と 100% 透過結合                    ・gcc / clang による単一バイナリ生成
 ・開発・試行錯誤時の REPL 駆動                        ・GIL フリー・ミリ秒起動・極小メモリ
```

### 3.1 Backend A: Python AST トランスパイラ (Python Interop モード)
- ILISP の AST を Python 標準の `ast.AST` にコンパイルし、`compile(tree, filename, 'exec')` を通じて CPython 上で実行。
- TCO は Python AST レベルでループへ展開、またはトランポリン（Trampoline）関数により実現。

### 3.2 Backend B: Native C99 AOT コンパイラ (Chicken Scheme / Nim 方式)
- ILISP の AST（CPS または ANF 形式）から、依存関係のないクリーンな C99 コードを出力。
- 各関数は C言語関数または関数ポインタテーブルに変換され、継続呼び出しは Chenc / Trampoline 方式により C スタックを消費しない。
- 外部 CPython ランタイムへの依存がゼロのスタンドアロン ELF / Mach-O 実行ファイルを生成。

---

## 4. Python 双方向相互運用プロトコル (Zero-Friction Interop)

### 4.1 ILISP から Python ライブラリの直接呼出
R7RS の `define-library` 機構を拡張し、`(ilisp python)` ライブラリを導入する。

```scheme
(import (scheme base)
        (scheme write)
        (ilisp python))

;; Python モジュールのインポート
(import-python (arxiv Search)
               (pathlib Path))

(define (fetch-crypto-papers limit)
  (let ((search (py-call Search :query "cat:cs.CR AND post-quantum" :max_results limit)))
    (py->list (py-call search 'results))))
```

### 4.2 Python から ILISP モジュールの透過インポート
Python の `sys.meta_path` に ILISP 用のファインダー・ローダー（`IlispFinder`）を登録することで、Python スクリプトから通常通り `.ilisp` ファイルを `import` 可能にする。

```python
# Python 側からの呼び出し
import ilisp.interop  # meta_path フックを登録
import my_pipeline  # my_pipeline.ilisp が透過的にロードされる

result = my_pipeline.harvest_papers(limit=10)
```

---

## 5. 現場復帰型コンディションシステム (Conditions & Restarts)

[DSN-29 (pylisp)](DSN-29-python_lisp_integrated_architecture_specification.md) で確立された「スタックを巻き戻さない現場復帰型例外機構」を、ILISP の言語機能として標準搭載する。

```scheme
;; 論文フェッチ関数 (回復手段 Restarts を提供)
(define (fetch-paper-resilient arxiv-id)
  (restart-case
      (http-get (format "https://arxiv.org/abs/~a" arxiv-id))
    (wait-and-retry (delay-sec)
      :report "指定秒数待機してリトライ"
      (sleep delay-sec)
      (fetch-paper-resilient arxiv-id))
    (fallback-to-rss ()
      :report "RSSフィードからメタデータを補完取得"
      (fetch-rss-metadata arxiv-id))
    (skip-paper ()
      :report "この論文をスキップして記録"
      (log-skipped-id arxiv-id)
      #f)))

;; 運用ポリシー側でハンドリング
(handler-bind
    (((http-error rate-limit)
      (lambda (c) (invoke-restart 'wait-and-retry 5)))
     ((pdf-error font-corrupted)
      (lambda (c) (invoke-restart 'fallback-to-rss))))
  (harvest-daily-batch))
```

---

## 6. ドメイン特化機能 (Domain Primitives)

### 6.1 S-OKF: ドキュメント同形性 (Document as S-Expression)
Google OKF v0.2 の YAML フロントマターおよび Markdown 本文を S式ツリーとしてネイティブ表現する。
文字列の結合処理を排除し、ツリーの走査・結合・サマリー抽出を純粋関数で行う。

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

### 6.2 パイプライン・スレッディングマクロ (`|>>`)
データの入力から加工、OKF変換、階層集計までを直感的なパイプラインとして結合。

### 6.3 記号推論 (miniKanren) 統合
[DSN-29](DSN-29-python_lisp_integrated_architecture_specification.md) の `logic.py` を基盤とし、MITRE ATT&CK や STRIDE 脅威モデルのルールベース推論をファーストクラスで実行。

---

## 7. 3段階セルフホスティング・ブートストラップ連鎖

```
[ compiler.ilisp ] ──────( Stage-0: Python compiler.py )──────▶ [ ilisp_stage1.c ]
                                                                       │ (gcc compile)
                                                                       ▼
                                                                [ ilisp-stage1 (bin) ]
                                                                       │
[ compiler.ilisp ] ──────( Stage-1: ilisp-stage1 )────────────▶ [ ilisp_stage2.c ]
                                                                       │ (gcc compile)
                                                                       ▼
                                                                [ ilisp-stage2 (bin) ]
                                                                       │
                         [ 不動点検証: diff ilisp_stage1.c ilisp_stage2.c == 0 ]
```

1. **Stage-0 (Python Host)**:
   - Pure Python で書かれた Reader、マクロ展開器、Cコード生成器。
   - `compiler.ilisp` を読み込み、最初のネイティブ実行ファイル `ilisp-stage1` をブートストラップ出力。
2. **Stage-1 (ILISP-in-ILISP)**:
   - ILISP 自身で書かれた完全な ILISP コンパイラ。
   - `ilisp-stage1` を使って自身を再コンパイルし、`ilisp-stage2` を生成。
3. **Stage-2 (Fixed-Point Verification)**:
   - `ilisp-stage1` が出力したコードと `ilisp-stage2` が出力したコードが完全一致（差分 0）することを自動テストで検証（不動点到達）。

---

## 8. ディレクトリ構成と自己完結ドキュメント体系 (`ilisp/docs/`)

ILISP は独立したパッケージとしてトップレベル `ilisp/` に集約され、将来の単独リポジトリ化・OSS化・PyPI配布に完全対応する。

```
ilisp/
├── docs/                          # ★ ILISP 自己完結ドキュメント体系 ★
│   ├── README.md                  # ILISP 概要・クイックスタート・理念
│   ├── SPEC_R7RS.md               # R7RS-small 準拠マトリクス・文法仕様
│   ├── PYTHON_INTEROP.md          # Python 双方向相互運用仕様
│   ├── MACROS_AND_CONDITIONS.md   # syntax-rules マクロ & コンディション詳細
│   └── BOOTSTRAP.md               # 3段階セルフホスティング連鎖仕様
├── compiler/                      # コンパイラコア (Reader, Lexer, AST, Macro)
├── backend/
│   ├── py_codegen/                # Python AST バックエンド
│   └── c_codegen/                 # Native C99 AOT バックエンド
├── runtime/                       # ランタイムコア (TCO, Environment, Primitives)
├── stdlib/                        # (scheme base), (ilisp ...) 標準ライブラリ
├── tests/                         # ILISP 独自テストスイート
└── repl.py                        # 対話型 REPL エントリーポイント
```

---

## 9. 品質ゲート・テスト戦略

本仕様書に基づくすべての実装は、リポジトリの品質基準（DoD）を満たす必要がある：
1. **R7RS 適合性テスト**: 標準 R7RS テストスイート（テストケース 200+ 件）の順次合格。
2. **Python Interop テスト**: Python クラスのインスタンス化、メソッド呼び出し、例外ハンドリングの透過性検証。
3. **ブートストラップ不動点テスト**: `make test-bootstrap` により、ステージ間コンパイル結果の差分ゼロを機械的に監査。
4. **トリプル品質ゲート**: `make check_format`, `make static_analysis`, `make test` の 100% PASS。

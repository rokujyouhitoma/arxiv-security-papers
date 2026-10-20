# ULisp 開発者・アーキテクチャ技術ガイド

本ディレクトリは、**ULisp (Underlying LISP)** ネイティブ AOT コンパイラの実装者およびコントリビューター向けの詳細技術リファレンスである。

システム全体における位置付け、高位設計思想、Tagged Pointer、ABI 規約については、正典仕様書である [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) を参照すること。

---

## 体系目次

1. [パイプライン・Nanopass 詳細仕様書](pipeline_architecture.md)
   - Pass 0〜Pass 8 の直列データフロー
   - 各パスの入出力 S 式形式と不変条件（Invariants）
   - 最適化パス（CP0, LVN, ANF, Annotator, RTyper, Contification, TBAA/Escape）
2. [低レベル IR (LIR) 命令セット仕様書](lir_specification.md)
   - 機械抽象 3 番地 LIR の S 式表現
   - 制御フロー、レジスタ/スタック転送、算術論理演算、ヒープアロケーション
   - マルチバックエンド（x86-64, AArch64, C/Wasm）マッピング規約
3. [ファーストクラス継続 (`call/cc`) & dynamic-wind 詳細技術仕様書](continuations_and_unwind.md)
   - R7RS Section 6.10 準拠の完全なファーストクラス継続
   - スタックセグメントコピー（Stack-Segment Copying）方式と 8MB クランプガード
   - LCA (Lowest Common Ancestor) 探索による unwind/rewind アルゴリズム
   - 多値連携・協調型コルーチン（Coroutine Generator）
4. [テストおよび検証ガイド](testing_guide.md)
   - パス別単体テスト（`tests/test_passes.scm`）
   - インクリメンタル E2E テスト（Phase 1〜7 / `test.sh`）
   - 3 段階ブートストラップ不動点検証（`diff stage2.s stage3.s == 0` / `bootstrap.sh`）
   - ファーストクラス継続 & dynamic-wind テスト（`test_call_cc.scm`）
   - Mytkowicz バイアス排除 差分テスト（`tools/differential_test_ulisp.py`）
5. [クロスプラットフォーム・コンパイル＆ビルド手順書 (macOS / Linux / BSD)](PORTABLE_BUILD_GUIDE.md)
   - Portable C バックエンド (`passes/07_backend_c.scm`) の利用方法
   - macOS (Apple Silicon / Intel Mac) および Linux/BSD でのコンパイル・ビルド・実行手順
   - `(!target c)` ディレクティブによるワンライナー生成と Clang/GCC によるネイティブバイナリ作成
   - メモリモデル、TCO、Darwin 固有のクラッシュハンドラ・`mmap` 互換性
6. [R7RS 仕様準拠状況リファレンス (R7RS-small / R7RS-large)](r7rs_specification_compliance.md)
   - R7RS-small (Section 4〜6 / 全16標準ライブラリ) の完全対応・部分対応・未対応機能一覧
   - R7RS-large (Red Edition, Tangerine Edition, 主要SRFI) の対応状況
   - AOT コンパイラとしての設計トレードオフと未実装機能ロードマップ
7. [3-Stage Bootstrap & 不動点自動検証プロトコル仕様書](bootstrap.md)
   - META II および不動点理論に基づくコンパイラ自己ホスト性（Self-Hosting）の数学的証明
   - Stage 0（シード）→ Stage 1 → Stage 2 → Stage 3 パイプライン
   - `make -C ulisp bootstrap_verify` ワンコマンド自動検証と bit-for-bit 完全一致判定（`diff stage2.s stage3.s == 0`）

---

## クイックリファレンス

### ディレクトリ構成
```text
ulisp/
├── Makefile                 # 単一 compiler.scm 結合・ビルド・テスト自動化
├── compiler.scm             # $(PASSES) を結合して自動生成されるコンパイラ本体
├── runtime.c                # Thin Debug Runtime (SIGSEGV トレース, 静的GCバッファ ulisp_gc_state[8], 最小 I/O)
├── test.sh                  # 全テストスイート実行スクリプト (Phase 1〜7)
├── test_c.sh                # Portable C バックエンド統合テスト
├── bootstrap.sh             # 3 段階セルフホスティング不動点検証スクリプト
├── lib/                     # Scheme 標準ライブラリ
│   ├── continuation.scm     # ファーストクラス継続 call/cc & dynamic-wind (Issue #540)
│   ├── values.scm           # R7RS 多値 values & call-with-values (Issue #538)
│   ├── exception.scm        # R7RS 例外 guard & raise (Issue #531)
│   ├── gc.scm               # Cheney's 2-Space コピー GC (完全ゼロアロケーション, Issue #501)
│   ├── posix.scm            # POSIX システムコール & I/O
│   ├── reader.scm           # 自前再帰下降 S 式パーサ (read)
│   ├── printer.scm          # S 式シリアライザ
│   └── string.scm           # 文字列操作・number->string
├── compiler/                # コンパイラ基盤ユーティリティ & ドライバ
│   ├── helpers.scm          # 共通AST操作・シンボル/ラベル生成
│   ├── primitives.scm       # プリミティブ述語分類・定数畳み込み
│   └── driver.scm           # コンパイルドライバ・CLI
├── passes/                  # 直列 Nanopass モジュール群 (3桁プレフィックス)
│   ├── 010_library.scm      # Pass 010: R7RS define-library & import (Issue #548)
│   ├── 020_macro_expander.scm # Pass 020: 衛生的マクロ展開器 (Issue #533)
│   ├── 030_desugar.scm      # Pass 030: 構文脱糖 (cond, case, let*, and, or, %raw-call/cc)
│   ├── 040_analysis.scm     # Pass 040: 静的スコープ・高速自由変数解析 (Issue #529)
│   ├── 050_cp0.scm          # Pass 050: CP0 最適化 (定数畳み込み, 自明分岐剪定, DCE)
│   ├── 060_lvn.scm          # Pass 060: ローカル値番号付け LVN (Issue #521)
│   ├── 070_anf.scm          # Pass 070: ANF 正規化 (3 番地コード化, Scoped Pool)
│   ├── 080_annotator.scm    # Pass 080: 抽象解釈型アノテータ (Issue #517)
│   ├── 090_rtyper.scm       # Pass 090: RType 推論 & アンボクシング (Issue #518)
│   ├── 100_contify.scm      # Pass 100: Contification 最適化 (Issue #522)
│   ├── 110_closure_convert.scm # Pass 110: クロージャ変換 (ラムダリフティング, フラット環境)
│   ├── 120_alias_escape.scm # Pass 120: TBAA & エスケープ解析 (Issue #525)
│   ├── 130_lir.scm          # Pass 130: 低レベル IR (LIR) 生成 (Issue #502)
│   ├── 131_lir_safepoint.scm # Pass 131: GC Safepoint & スタックマップ生成 (Issue #519)
│   ├── 132_lir_braun_ssa.scm # Pass 132: Braun SSA & ブロック引数 (Issue #523)
│   ├── 140_backend_x86_64.scm # Pass 140: x86-64 GNU アセンブリコード生成
│   ├── 150_backend_aarch64.scm # Pass 150: AArch64 GNU アセンブリコード生成
│   └── 160_backend_c.scm    # Pass 160: Portable C99 コード生成 (Issue #504)
├── tests/                   # 統合テストスイート
│   ├── test_call_cc.scm     # call/cc & dynamic-wind テスト (Issue #540)
│   ├── test_passes.scm      # Nanopass 単体テスト
│   └── ...
└── docs/                    # 本技術リファレンス
    ├── README.md
    ├── pipeline_architecture.md
    ├── lir_specification.md
    ├── continuations_and_unwind.md
    ├── testing_guide.md
    └── r7rs_specification_compliance.md
```

### 主要コマンド
```bash
# 全テスト (Phase 1〜7 + ブートストラップ不動点検証) の実行
make test

# 3段階セルフホスティング不動点検証のみ実行 (diff stage2.s stage3.s == 0)
make bootstrap

# 単一式 (例: 42) のクイックコンパイル・実行
make run_42
```

---

## 4. ランタイム・ガベージコレクションアーキテクチャ (Issue #501)

- **完全自前 Cheney's 2-Space Copying GC (`lib/gc.scm`)**:
  - Scheme の末尾再帰で記述された精密型コピーコレクタ。
  - コレクション実行中のヒープアロケーション 0 バイト（完全ゼロアロケーション）。
- **Thin C Cushion (`runtime.c`)**:
  - 静的状態配列 `uint64_t ulisp_gc_state[8];` の 1 行のみで Scheme と連携。
  - C 側の肥大化を完全阻止し、保守性と移植性を最大化。
- **8B Prefix Header & ポインタ抽象化**:
  - ヒープオブジェクト直前に Fixnum タグ付き 8B ヘッダ（型、ペイロードサイズ）を配置。
  - コピー後は転送先ポインタを直接ヘッダへ上書き。
  - スタック最深部 `deepest-sp` から開始時のスタック天井（`gc-bottom`）まで全フレームを精密走査。


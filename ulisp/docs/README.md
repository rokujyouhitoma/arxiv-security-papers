# ULisp 開発者・アーキテクチャ技術ガイド

本ディレクトリは、**ULisp (Underlying LISP)** ネイティブ AOT コンパイラの実装者およびコントリビューター向けの詳細技術リファレンスである。

システム全体における位置付け、高位設計思想、Tagged Pointer、ABI 規約については、正典仕様書である [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) を参照すること。

---

## 体系目次 (Documentation Catalog)

ULisp のドキュメント群は、役割プレフィックス命名規約（`spec_` 仕様書、`guide_` 手順書、`ref_` 規格リファレンス）に基づいて体系化されています。

```text
ulisp/docs/
├── spec_*.md       # アーキテクチャ・中間言語・ランタイム仕様書
├── guide_*.md      # ビルド・テスト・セルフホスト検証手順書
└── ref_*.md        # Scheme 標準規格 (R7RS) 準拠状況リファレンス
```

### 1. 設計・アーキテクチャ仕様書 (`spec_*.md`)

1. **[パイプライン・Nanopass 詳細仕様書](spec_pipeline.md)** (`spec_pipeline.md`)
   - 3層物理分離（Frontend / LIR / Backend）パイプラインデータフロー
   - Pass 010〜160 の入出力 S 式形式と不変条件（Invariants）
   - 最適化パス（CP0, LVN, ANF, Annotator, RTyper, Contification, TBAA/Escape）
2. **[Nanopass Framework 言語仕様書 (自動生成)](spec_nanopass.md)** (`spec_nanopass.md`)
   - 中間言語定義（`L_src`, `L_core` 等）の終端・非終端構文規則
   - 言語継承・構文遷移図（Mermaid Derivation Graph）
   - `ulisp/tools/generate_nanopass_docs.scm` による完全自動生成仕様
3. **[低レベル IR (LIR) 正典仕様書](spec_lir.md)** (`spec_lir.md`)
   - 機械抽象 3 番地 LIR の S 式正典構文（`%lir-program`）
   - 制御フロー、レジスタ/スタック転送、算術論理演算、ヒープアロケーション
   - Canonical LIR 境界契約と多層バリデータ（`lir_verifier.scm`）
4. **[ファーストクラス継続 (`call/cc`) & dynamic-wind 技術仕様書](spec_continuations_and_unwind.md)** (`spec_continuations_and_unwind.md`)
   - R7RS Section 6.10 準拠の完全なファーストクラス継続
   - スタックセグメントコピー（Stack-Segment Copying）方式と 8MB クランプガード
   - LCA (Lowest Common Ancestor) 探索による unwind/rewind アルゴリズム
   - 多値連携・協調型コルーチン（Coroutine Generator）
5. **[ガベージコレクション & メモリモデル仕様書](spec_gc_and_memory.md)** (`spec_gc_and_memory.md`)
   - 64-bit Tagged Pointer メモリモデル（Fixnum `00`, Heap `01`, Symbol `10`, 即値 `0x2F`〜`0x6F`）
   - Cheney 2-Space コピー GC アーキテクチャと完全ゼロアロケーション走査
   - GC Safepoint、スタックマップ生成（Pass 131）、およびエスケープ解析（Pass 120）
6. **[バックエンド & コード生成仕様書](spec_backend.md)** (`spec_backend.md`)
   - マルチターゲット（x86-64 Linux, AArch64 Linux, Portable C99）コード生成
   - Calling Convention（引数・戻り値・Callee-saved レジスタ）
   - 末尾呼出最適化（TCO: Tail-Call Optimization）と直接ジャンプ変換
   - ベアメタル・システムコール直発行（`%syscall`）と libc 依存ゼロ設計

### 2. 開発・検証・ビルド手順書 (`guide_*.md`)

1. **[クロスプラットフォーム・コンパイル＆ビルド手順書 (macOS / Linux / BSD)](guide_portable_build.md)** (`guide_portable_build.md`)
   - Portable C バックエンド (`backend/160_backend_c.scm`) の利用方法
   - macOS (Apple Silicon / Intel Mac) および Linux/BSD でのビルド・実行手順
   - `(!target c)` ディレクティブによる C99 生成と Clang/GCC ネイティブバイナリ作成
2. **[テストおよび検証ガイド](guide_testing.md)** (`guide_testing.md`)
   - パス別単体テスト（`tests/test_passes.scm`, `tests/passes/`）
   - インクリメンタル E2E テスト（Phase 1〜7 / `test.sh`）
   - 3 段階ブートストラップ不動点検証（`diff stage2.s stage3.s == 0` / `bootstrap.sh`）
   - ファーストクラス継続 & dynamic-wind テスト（`test_call_cc.scm`）
   - Mytkowicz バイアス排除 差分テスト（`tools/differential_test_ulisp.py`）
   - 階層化 LIR 単体テスト（`test_lir.sh` & `test_backend.sh`）
3. **[3-Stage Bootstrap & 不動点自動検証プロトコル仕様書](guide_bootstrap.md)** (`guide_bootstrap.md`)
   - META II および不動点理論に基づくコンパイラ自己ホスト性（Self-Hosting）の数学的証明
   - Stage 0（シード）→ Stage 1 → Stage 2 → Stage 3 パイプライン
   - `make -C ulisp bootstrap_verify` ワンコマンド自動検証と bit-for-bit 完全一致判定

### 3. 言語規格・リファレンス (`ref_*.md`)

1. **[R7RS 仕様準拠状況リファレンス (R7RS-small / R7RS-large)](ref_r7rs_compliance.md)** (`ref_r7rs_compliance.md`)
   - R7RS-small (Section 4〜6 / 全16標準ライブラリ) の完全対応・部分対応・未対応機能一覧
   - R7RS-large (Red Edition, Tangerine Edition, 主要SRFI) の対応状況
   - AOT コンパイラとしての設計トレードオフと未実装機能ロードマップ

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
├── test_lir.sh              # LIR 中間出力・フロントエンド検証スクリプト
├── test_backend.sh          # バックエンド独立検証スクリプト
├── bootstrap.sh             # 3 段階セルフホスティング不動点検証スクリプト
├── lib/                     # Scheme 標準ライブラリ (.scm / .sld)
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
│   ├── verifier.scm         # 軽量 IR Verifier フレームワーク (Issue #576)
│   └── driver.scm           # コンパイルドライバ・CLI
├── frontend/                # Frontend メタコンパイラ層 (Pass 010〜120)
│   ├── 010_library.scm      # Pass 010: R7RS define-library & import (Issue #548)
│   ├── 015_dsl_expander.scm # Pass 015: Nanopass DSL 手続き型展開 (Issue #587)
│   ├── 020_macro_expander.scm # Pass 020: 衛生的マクロ展開器 (Issue #533)
│   ├── 025_top_level.scm    # Pass 025: トップレベル定義巻き上げ (Issue #570)
│   ├── 026_029_desugar_*.scm# Pass 026-029: 構文別脱糖 (Issue #574)
│   ├── 030_desugar.scm      # Pass 030: 構文脱糖 (cond, case, let*, and, or, %raw-call/cc)
│   ├── 040_analysis.scm     # Pass 040: 静的スコープ・高速自由変数解析 (Issue #529)
│   ├── 050_cp0.scm          # Pass 050: CP0 最適化 (定数畳み込み, 自明分岐剪定, DCE)
│   ├── 060_lvn.scm          # Pass 060: ローカル値番号付け LVN (Issue #521)
│   ├── 070_anf.scm          # Pass 070: ANF 正規化 (3 番地コード化, Scoped Pool)
│   ├── 080_annotator.scm    # Pass 080: 抽象解釈型アノテータ (Issue #517)
│   ├── 090_rtyper.scm       # Pass 090: RType 推論 & アンボクシング (Issue #518)
│   ├── 100_contify.scm      # Pass 100: Contification 最適化 (Issue #522)
│   ├── 110_closure_convert.scm # Pass 110: クロージャ変換 (ラムダリフティング, フラット環境)
│   └── 120_alias_escape.scm # Pass 120: TBAA & エスケープ解析 (Issue #525)
├── lir/                     # LIR / Middle-End 中間表現層 (Pass 123〜132)
│   ├── lir_lang.scm         # Canonical LIR 形式言語仕様 define-language L_lir_canonical (Issue #593)
│   ├── lir_verifier.scm     # Canonical LIR バリデータ (Issue #589)
│   ├── 123_127_lir_*.scm    # Pass 123-127: 機能責務別 LIR 低レベル化 (Issue #583)
│   ├── 128_lir_branch_fusion.scm # Pass 128: 分岐融合 (Issue #571)
│   ├── 129_lir_primitives.scm # Pass 129: 命令選択 (Issue #573)
│   ├── 130_lir.scm          # Pass 130: 低レベル IR (LIR) 生成 (Issue #502)
│   ├── 131_lir_safepoint.scm # Pass 131: GC Safepoint & スタックマップ生成 (Issue #519)
│   └── 132_lir_braun_ssa.scm # Pass 132: Braun SSA & ブロック引数 (Issue #523)
├── backend/                 # Backend コード生成層 (Pass 140〜160)
│   ├── 140_backend_x86_64.scm # Pass 140: x86-64 GNU アセンブリコード生成
│   ├── 141_backend_x86_gc.scm # Pass 141: x86 世代別コピー GC ルーチン (Issue #569)
│   ├── 142_backend_x86_freestanding.scm # Pass 142: x86 ベアメタルランタイム (Issue #569)
│   ├── 150_backend_aarch64.scm # Pass 150: AArch64 GNU アセンブリコード生成
│   └── 160_backend_c.scm    # Pass 160: Portable C99 コード生成 (Issue #504)
├── tests/                   # 統合テストスイート
│   ├── passes/              # 各 Nanopass 1:1 対応単体テスト (Issue #572)
│   ├── test_call_cc.scm     # call/cc & dynamic-wind テスト (Issue #540)
│   ├── test_passes.scm      # Nanopass 単体テスト
│   └── ...
└── docs/                    # 本技術リファレンス
    ├── README.md            # 総合目次 (本ファイル)
    ├── spec_pipeline.md     # パイプライン・Nanopass 詳細仕様書
    ├── spec_nanopass.md     # Nanopass Framework 言語仕様書 (自動生成)
    ├── spec_lir.md          # Canonical 低レベル IR 正典仕様書
    ├── spec_continuations_and_unwind.md # ファーストクラス継続技術仕様書
    ├── spec_gc_and_memory.md# GC & メモリモデル仕様書
    ├── spec_backend.md      # バックエンド & コード生成仕様書
    ├── guide_portable_build.md # ポータブル C ビルド手順書
    ├── guide_testing.md     # テストおよび検証ガイド
    ├── guide_bootstrap.md   # 3-Stage Bootstrap 仕様書
    └── ref_r7rs_compliance.md # R7RS 言語仕様準拠状況リファレンス
```

### 主要コマンド
```bash
# 全テスト (Phase 1〜7 + ブートストラップ不動点検証) の実行
make test

# 階層化テスト (Frontend LIR 単体テスト + Backend 単体テスト)
make test_lir
make test_backend

# 3段階セルフホスティング不動点検証のみ実行 (diff stage2.s stage3.s == 0)
make bootstrap

# Nanopass 言語仕様書の自動再生成
make docs_nanopass

# 単一式 (例: 42) のクイックコンパイル・実行
make run_42
make run_c_42
```

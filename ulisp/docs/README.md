# ULisp 開発者・アーキテクチャ技術ガイド

本ディレクトリは、**ULisp (Underlying LISP)** ネイティブ AOT コンパイラの実装者およびコントリビューター向けの詳細技術リファレンスである。

システム全体における位置付け、高位設計思想、Tagged Pointer、ABI 規約については、正典仕様書である [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) を参照すること。

---

## 体系目次

1. [パイプライン・Nanopass 詳細仕様書](pipeline_architecture.md)
   - Pass 0〜Pass 8 の直列データフロー
   - 各パスの入出力 S 式形式と不変条件（Invariants）
   - パス間の疎結合性とセルフホスティング制約
2. [低レベル IR (LIR) 命令セット仕様書](lir_specification.md)
   - 機械抽象 3 番地 LIR の S 式表現
   - 制御フロー、レジスタ/スタック転送、算術論理演算、ヒープアロケーション
   - マルチバックエンド（x86-64, AArch64, C/Wasm）マッピング規約
3. [テストおよび検証ガイド](testing_guide.md)
   - パス別単体テスト（`tests/test_passes.scm`）
   - インクリメンタル E2E テスト（Phase 1〜7 / `test.sh`）
   - 3 段階ブートストラップ不動点検証（`diff stage2.s stage3.s == 0` / `bootstrap.sh`）
   - ILisp AOT バックエンド統合テスト（`pytest tests/ilisp/`）

---

## クイックリファレンス

### ディレクトリ構成
```text
ulisp/
├── Makefile                 # 単一 compiler.scm 結合・ビルド・テスト自動化
├── compiler.scm             # $(PASSES) を結合して自動生成されるコンパイラ本体
├── runtime.c                # Thin Debug Runtime (SIGSEGV トレース, 1GB ヒープ, 最小 I/O)
├── test.sh                  # 全テストスイート実行スクリプト (Phase 1〜7)
├── bootstrap.sh             # 3 段階セルフホスティング不動点検証スクリプト
├── lib/                     # Scheme 標準ライブラリ
│   ├── string.scm           # 文字列操作・number->string
│   ├── printer.scm          # S 式シリアライザ
│   └── reader.scm           # 自前再帰下降 S 式パーサ (read)
├── passes/                  # 直列 Nanopass モジュール群
│   ├── 00_helpers.scm       # 共通述語・アキュムレータ
│   ├── 01_desugar.scm       # Pass 1: 構文脱糖 (cond, case, let*, and, or)
│   ├── 02_analysis.scm      # Pass 2: 静的スコープ・自由変数解析
│   ├── 03_cp0.scm           # Pass 3: CP0 最適化 (定数畳み込み, 自明分岐剪定, DCE)
│   ├── 04_anf.scm           # Pass 4: ANF 正規化 (3 番地コード化, Scoped Pool)
│   ├── 05_closure_convert.scm # Pass 5: クロージャ変換 (ラムダリフティング, フラット環境)
│   ├── 06_emitter.scm       # Pass 6: GNU アセンブリ出力ヘルパー
│   ├── 07_codegen.scm       # Pass 7: x86-64 ネイティブコード生成
│   └── 08_driver.scm        # Pass 8: コンパイルドライバ・CLI
└── docs/                    # 本技術リファレンス
    ├── README.md
    ├── pipeline_architecture.md
    ├── lir_specification.md
    └── testing_guide.md
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

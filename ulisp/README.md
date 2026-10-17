# ULisp (Underlying LISP)

**ULisp** は、Abdulaziz Ghuloum 氏の古典的論文 *"An Incremental Approach to Compiler Construction"* および植山類氏の *compilerbook* のインクリメンタル TDD 手法に基づき、Scheme サブセットから **x86-64 Linux 向けネイティブコード（GAS / ELF）** を出力する自己完結型セルフホスティングコンパイラです。

- **包括設計仕様書（正典）**: [DSN-33 (ULISP 包括設計仕様書)](../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **開発者テクニカルリファレンス**: [ulisp/docs/README.md](docs/README.md)
  - [パイプライン・Nanopass 詳細仕様書](docs/pipeline_architecture.md)
  - [低レベル IR (LIR) 命令セット仕様書](docs/lir_specification.md)
  - [ファーストクラス継続 & dynamic-wind 詳細技術仕様書](docs/continuations_and_unwind.md)
  - [テストおよび検証ガイド](docs/testing_guide.md)

---

## 1. 「A, I, U」三位一体アーキテクチャにおける位置づけ

```text
┌─────────────────────────────────────────────────────────────────┐
│ ALisp (Agent Lisp / DSN-32)       : AIエージェント安全保証層    │
├─────────────────────────────────────────────────────────────────┤
│ ILisp (Infrastructure / DSN-31)   : R7RS標準・推論・Python連携層│
├─────────────────────────────────────────────────────────────────┤
│ ULisp (Underlying Lisp / DSN-33)  : x86-64 ネイティブ金属直結層 │
└─────────────────────────────────────────────────────────────────┘
```

ULisp は将来的に **ILisp の「Backend B: Native AOT コンパイラ」** として結合され、ILisp/ALisp のコードを外部依存ゼロの単一 ELF バイナリへ直接コンパイルします。

---

## 2. クイックスタート

```bash
# Phase 1〜7 テストスイートの実行
cd ulisp
make test

# R7RS ファーストクラス継続 & dynamic-wind テスト (7 シナリオ 100% PASS)
make test_call_cc

# 3段階セルフホスティングブートストラップ連鎖および不動点検証 (シード駆動 Fast Bootstrap: ~15秒)
make bootstrap

# 完全検証ブートストラップ (ILisp / Python 経由)
FULL_BOOTSTRAP=1 make bootstrap

# Mytkowicz バイアス排除 差分テスト (Gauche / Chibi / Chez 100% 一致)
python3 tools/differential_test_ulisp.py

# 整数 42 のコンパイル＆実行デモ
make run_42
```

---

## 3. ロードマップ進捗状況

| フェーズ | ステップ | 内容 | ステータス |
| :--- | :--- | :--- | :---: |
| **Phase 1** | **Step 1** | 整数 1 個のコンパイル (`42` -> `mov rax, 168`) | 🟢 **完了** |
| | **Step 2** | 即値リテラル (`#t`, `#f`, `'()`, `#\a`) | 🟢 **完了** |
| | **Step 3** | 単項数値演算 (`fxadd1`, `fxsub1`, `fixnum->char`, `char->fixnum`) | 🟢 **完了** |
| | **Step 4** | 単項型述語 (`fixnum?`, `boolean?`, `char?`, `null?`, `zero?`) | 🟢 **完了** |
| **Phase 2** | **Step 5** | 二項算術演算 (`+`, `-`) | 🟢 **完了** |
| | **Step 6** | 多項算術・比較演算 (`*`, `=`, `<`, `<=`, `>`, `>=`) | 🟢 **完了** |
| | **Step 7** | 局所変数 (`let` 式) | 🟢 **完了** |
| | **Step 8** | ネストした `let` 式と変数シャドウイング | 🟢 **完了** |
| **Phase 3** | **Step 9** | 条件分岐 (`if` 式) と真偽値規則 | 🟢 **完了** |
| | **Step 10** | 論理演算の脱糖 (`and`, `or`, `not`) | 🟢 **完了** |
| | **Step 11** | 複文 (`begin` 式) | 🟢 **完了** |
| **Phase 4** | **Step 12** | 128MB バンプアロケータ (`R12`) | 🟢 **完了** |
| | **Step 13** | ペアとリスト (`cons`, `car`, `cdr`, `pair?`) | 🟢 **完了** |
| | **Step 14** | 破壊的代入 (`set-car!`, `set-cdr!`) | 🟢 **完了** |
| | **Step 15** | クォート構文 (`quote`, リスト定数リテラル) | 🟢 **完了** |
| | **Step 16** | ポインタ等値判定 (`eq?`, シンボルインターン) | 🟢 **完了** |
| **Phase 5** | **Step 17** | 手続き呼び出し規約・多引数関数 (`lambda`, call) | 🟢 **完了** |
| | **Step 18** | 末尾呼び出し最適化 TCO (スタック $O(1)$、100万回再帰) | 🟢 **完了** |
| | **Step 19** | 静的自由変数解析 (`free-vars`) | 🟢 **完了** |
| | **Step 20** | フラットクロージャ・カリー化・高階関数・自己再帰 (`letrec`) | 🟢 **完了** |
| **Phase 6** | **Step 21** | 最小 I/O プリミティブ (`read-char`, `peek-char`, `write-char`, `eof-object?`) | 🟢 **完了** |
| | **Step 22** | 手書き再帰下降 S式リーダー (`read`: リスト, ドット対, クォート) | 🟢 **完了** |
| | **Step 23** | 構文脱糖パス (`cond`, `let*`, 暗黙の `begin` 複数本体式) | 🟢 **完了** |
| | **Step 24** | 相互再帰バックパッチによる自己完結型リーダー基盤の確立 | 🟢 **完了** |
| **Phase 7** | **Step 25** | コンパイラの自己充足化 (`compiler.scm` が ULisp 自己構文で記述) | 🟢 **完了** |
| | **Step 26** | 3段階ブートストラップ連鎖 (`ILisp` $\to$ `stage1` $\to$ `stage2` $\to$ `stage3`) | 🟢 **完了** |
| | **Step 27** | アセンブリ不動点検証 (`cmp stage2.s stage3.s` 差分ゼロ) | 🟢 **完了** |
| **Phase 8** | **Step 28** | 静的シンボルテーブルのインターン化と不要コード削除 (Issue #528) | 🟢 **完了** |
| | **Step 29** | 自由変数解析のビットセット最適化と高速モジュール分離 (Issue #529) | 🟢 **完了** |
| | **Step 30** | プラガブル GC 指向および Arena モード切替ディレクティブ (Issue #530) | 🟢 **完了** |
| | **Step 31** | Mytkowicz バイアス排除フレームワークと外部 Scheme 差分テスト (Issue #526) | 🟢 **完了** |
| **Phase 9** | **Step 32** | R7RS 準拠 例外ハンドリング機構 (`guard`, `raise`) (Issue #531) | 🟢 **完了** |
| | **Step 33** | R7RS 準拠 多値ゼロヒープ受け渡し (`values`, `call-with-values`) (Issue #538) | 🟢 **完了** |
| | **Step 34** | R7RS 準拠 完全なファーストクラス継続 (`call/cc`, `dynamic-wind`) (Issue #540) | 🟢 **完了** |

---

## 4. 統一 RPython スタイル 3 層アーキテクチャ (Issue #514)

ULisp は AOT 単体コンパイラから、RPython の設計思想（`translator` + `jit` + `memory` + `rlib`）を直接取り入れた **統一ハイパフォーマンス・メタプログラミング言語基盤** へと統合・昇格されました。

### (1) 3層アーキテクチャ階層構造

```text
ulisp/
├── passes/       ; [Layer 1: AOT Substrate] Nanopass コンパイラ (Pass 00〜07)
│                 ; 決定論的自己ホスティング (diff stage2.s stage3.s == 0) を死守
├── jit/          ; [Layer 3: Meta-Tracing JIT] (旧 MLisp から完全統合)
│   ├── core/     ; 限定継続 shift/reset, mini-eval
│   ├── tracer/   ; メタトレーサ, auto_instrument (ループ自動検知)
│   ├── optimizer/; 部分評価器 (PE), 仮想オブジェクト除去 (Virtuals)
│   ├── bridge/   ; トレース -> ULisp Canonical LIR 変換アダプタ
│   └── runtime/  ; W^X 実行可能 JIT バッファ管理
├── gc/           ; [Layer 2: Memory & GC] プラガブルGC (2空間 Copying GC, Bump)
├── lib/          ; [Layer 2: Standard Substrate] rlib 相当 (rposix, rstring, rdict, rjit スタブ)
├── driver/       ; 統一 CLI ドライバ
│   ├── compile.scm ; AOT Nanopass バッチコンパイラ
│   └── jit.scm     ; JIT 対応動的ランタイム & AOT デュアルディスパッチャ
├── tests/        ; 統合テストスイート (AOT パステスト + JIT 94テスト)
├── benchmarks/   ; 性能評価スイート (scheme-stage2 vs ulisp-jit)
└── Makefile      ; 統一ビルド (bootstrap, test, jit, bench, clean)
```

### (2) RPython との対応マッピング

| RPython コンポーネント | ULisp 統合アーキテクチャ | 役割 |
| :--- | :--- | :--- |
| **`rpython.translator`** | **`ulisp/passes/` & `compiler.scm`** | AST 脱糖・CP0・ANF・クロージャ変換・LIR・ネイティブアセンブリ生成 |
| **`rpython.jit`** | **`ulisp/jit/`** | 限定継続、ホットループ検知、トレース記録、部分評価、LIR ブリッジ |
| **`rpython.memory`** | **`ulisp/gc/` & `lib/gc.scm`** | バンプアロケータ、2空間 Cheney Copying GC、アロケーションバリア |
| **`rpython.rlib`** | **`ulisp/lib/`** | `rposix` (I/O, プロセス), `rstring`, `rdict`, `rjit` (JIT ヒント/スタブ) |
| **`pypy-c` / CLI** | **`ulisp/bin/ulisp-jit`** | AOT コンパイルと JIT 動的評価を単一バイナリで提供するワンバイナリ |

### (3) レイヤード・ブートストラップ（Layered Bootstrap）の保証
- **自己ホスティング不動点保証の保護**:
  `make bootstrap` は極小・決定論的な **Layer 1 (`passes/` + `lib/`)** のみで実行され、`stage2.s` と `stage3.s` のビット完全一致（`diff == 0`）を永久に保証します。
- **プラグイン型 JIT 拡張**:
  Layer 3 の JIT エンジンは、Layer 1 の自己ホスティング AOT コンパイラによってネイティブ ELF バイナリ `bin/ulisp-jit` としてコンパイル・生成されます。



# ULisp (Underlying LISP)

**ULisp** は、Abdulaziz Ghuloum 氏の古典的論文 *"An Incremental Approach to Compiler Construction"* および植山類氏の *compilerbook* のインクリメンタル TDD 手法に基づき、Scheme サブセットから **x86-64 Linux 向けネイティブコード（GAS / ELF）** を出力する自己完結型セルフホスティングコンパイラです。

設計仕様書: [DSN-33 (ULISP Underlying x86-64 Native AOT Compiler Architecture Specification)](../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)

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

# 3段階セルフホスティングブートストラップ連鎖および不動点検証
make bootstrap

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


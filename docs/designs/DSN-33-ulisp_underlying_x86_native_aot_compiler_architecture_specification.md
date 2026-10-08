# [DSN-33] ULISP (Underlying LISP) x86-64 ネイティブ AOT コンパイラ包括設計仕様書
## 〜 ILisp ブートストラップから x86-64 Linux ELF 直結・Tagged Pointer・バンプアロケータ・TCO/フラットクロージャ・ILisp AOT バックエンド統合 〜

- **文書番号**: `DSN-33`
- **文書ステータス**: `APPROVED`
- **対象サブシステム**:
  - `ulisp/` (ULISP コアプロジェクト / 独立サンドボックス・リポジトリ)
  - `ulisp/compiler.scm` (x86-64 Scheme ネイティブ AOT コンパイラ本体)
  - `ulisp/lib/` (Scheme 標準ライブラリ: `string.scm`, `printer.scm`, `reader.scm`)
  - `ulisp/runtime.c` (Thin Debug Runtime / SIGSEGV backtrace / 16バイトアライメント / 1GB バンプアロケータ / 最小 3 I/O primitives)
  - `ulisp/test.sh` (compilerbook 準拠・インクリメンタル自動テストランナー)
  - `ilisp/backend/ulisp_codegen/` (ILisp 連携: DSN-31 Backend B 向け ULisp AOT トランスパイラ)
  - `docs/designs/` (設計書体系)
- **関連設計書**:
  - [DSN-01 (High-Level Architecture)](DSN-01-high_level_design.md)
  - [DSN-29 (Python-LISP Integrated Architecture Specification - pylisp)](DSN-29-python_lisp_integrated_architecture_specification.md)
  - [DSN-31 (ILISP R7RS Core Architecture Specification)](DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
  - [DSN-32 (AILisp Agent Lisp Architecture Specification)](DSN-32-ailisp_agent_lisp_architecture_specification.md)
- **【主査・報告】 IT Specialist (Programming Languages & Compilers / PLC) / Systems Architect (SA)**
- **【共同主査】 Project Manager (PM) / Software Development (SWD) / Software Quality Assurance Specialist (QA)**
- **【参画・協調】 16 大専門エージェント全員 (PM, SEC, SA, QA, DBA, NET, NLP, STR, SM, EMB, AUD, DES, EDU, SWD, APS, PLC)**

---

## 体系目次

- [0. 概要と基本方針 (Executive Summary)](#0-概要と基本方針-executive-summary)
- [1. 「A, I, U」三位一体（Trinity）言語アーキテクチャ](#1-a-i-u-三位一体trinity言語アーキテクチャ)
  - [1.1 命名哲学とレイヤー役割分担 (Agent ── Infrastructure ── Underlying)](#11-命名哲学とレイヤー役割分担-agent----infrastructure----underlying)
  - [1.2 ULisp のアイデンティティと責務](#12-ulisp-のアイデンティティと責務)
- [2. アーキテクチャ基本設計とハードウェア・ABI 整合](#2-アーキテクチャ基本設計とハードウェアabi-整合)
  - [2.1 64ビット Tagged Pointer メモリモデル](#21-64ビット-tagged-pointer-メモリモデル)
  - [2.2 レジスタ割り当て・スタックフレーム・ABI 規約](#22-レジスタ割り当てスタックフレームabi-規約)
  - [2.3 ゼロGC・高速バンプアロケータ戦略](#23-ゼロgc高速バンプアロケータ戦略)
  - [2.4 シンボル表現と決定論的インターン（Interning）テーブル](#24-シンボル表現と決定論的インターンinterningテーブル)
- [3. 言語機能と低レイヤコード生成仕様](#3-言語機能と低レイヤコード生成仕様)
  - [3.1 即値・単項演算・述語](#31-即値単項演算述語)
  - [3.2 局所変数 (`let`) とスタックマッピング](#32-局所変数-let-とスタックマッピング)
  - [3.3 条件分岐 (`if`) と論理演算の脱糖](#33-条件分岐-if-と論理演算の脱糖)
  - [3.4 ペアとリストプリミティブ (`cons`, `car`, `cdr`, `quote`)](#34-ペアとリストプリミティブ-cons-car-cdr-quote)
  - [3.5 末尾呼び出し最適化 (Tail Call Optimization: TCO)](#35-末尾呼び出し最適化-tail-call-optimization-tco)
  - [3.6 第一級関数とフラットクロージャ (Flat Closures)](#36-第一級関数とフラットクロージャ-flat-closures)
  - [3.7 手書き再帰下降 S式リーダー (`read`) とシステムコール I/O](#37-手書き再帰下降-s式リーダー-read-とシステムコール-io)
- [4. インクリメンタル開発ロードマップ (全7フェーズ・27ステップ)](#4-インクリメンタル開発ロードマップ-全7フェーズ27ステップ)
- [5. 3段階セルフホスティングブートストラップ連鎖と不動点検証](#5-3段階セルフホスティングブートストラップ連鎖と不動点検証)
  - [5.1 ブートストラップ連鎖 (Stage 1 〜 Stage 3)](#51-ブートストラップ連鎖-stage-1--stage-3)
  - [5.2 決定論的コード生成と完全一致検証 (`diff` ゼロ保証)](#52-決定論的コード生成と完全一致検証-diff-ゼロ保証)
- [6. ILisp AOT バックエンド統合仕様 (DSN-31 Backend B への昇格)](#6-ilisp-aot-バックエンド統合仕様-dsn-31-backend-b-への昇格)
  - [6.1 統合アーキテクチャと依存性境界](#61-統合アーキテクチャと依存性境界)
  - [6.2 ILisp S式 AST から ULisp 入力へのコンパイルパイプライン](#62-ilisp-s式-ast-から-ulisp-入力へのコンパイルパイプライン)
  - [6.3 ランタイム共有とネイティブ ELF 単一バイナリ生成](#63-ランタイム共有とネイティブ-elf-単一バイナリ生成)
- [7. ディレクトリ構成と開発運用プロトコル](#7-ディレクトリ構成と開発運用プロトコル)
- [8. 品質ゲート・テスト自動化](#8-品質ゲートテスト自動化)

---

## 0. 概要と基本方針 (Executive Summary)

本仕様書は、学術論文セキュリティ解析・OKF ナレッジベース構築プラットフォームにおける最下層の実行基盤として、**ULISP (Underlying LISP)** を設計・定義するものである。

ULISP は、Abdulaziz Ghuloum 氏の古典的論文 *"An Incremental Approach to Compiler Construction"* および植山類氏の *compilerbook* によるインクリメンタル TDD 手法を直交統合し、**三位一体のホスト処理系 ILisp（`python3 -m ilisp`）によるブートストラップから開始して x86-64 Linux 向けネイティブアセンブリ（GAS / ELF）を出力する完全独立のセルフホスティングコンパイラ**である。

完成した ULISP は、単なる教育的・スタンドアロンなコンパイラにとどまらず、**[DSN-31 (ILISP)] の「Backend B: Native AOT コンパイラ」の中核コード生成エンジン**として正式に結合され、ILISP/ALisp で記述されたセキュリティ解析パイプライン・推論ロジックを極小・超高速なネイティブ単一バイナリへと AOT コンパイルする役割を担う。

---

## 1. 「A, I, U」三位一体（Trinity）言語アーキテクチャ

### 1.1 命名哲学とレイヤー役割分担 (Agent ── Infrastructure ── Underlying)

本プラットフォームの言語処理系群は、**「A, I, U（あ・い・う）」** の三層垂直統合アーキテクチャを形成する。

```
+===============================================================================+
|                   ALisp (Agent & Assurance Layer / DSN-32)                    |
|   - AI コーディングエージェント安全統制 (Bounded Autonomy)                    |
|   - 計算量制御 (with-fuel), 権限境界 (with-caps), 契約 (define/c)            |
|   - S-Path 決定論的 AST 自己修復 & SafePyProxy 脱獄防御                       |
+===============================================================================+
                                       │
                                       ▼ [マクロ脱糖 / AST 委譲]
+===============================================================================+
|                 ILisp (Infrastructure & Intelligence Layer / DSN-31)          |
|   - R7RS-small Scheme 世界標準仕様準拠・完全数値タワー                        |
|   - Scope Sets 衛生的マクロ展開器 (syntax-rules)                              |
|   - Python ゼロコピー相互運用 (SequenceView) & miniKanren 記号推論            |
|   - Tree-walk 高速評価器 & 段階的バックエンド統括                             |
+===============================================================================+
                                       │
                                       ▼ [AOT コンパイル委譲 (DSN-31 Backend B)]
+===============================================================================+
|                   ULisp (Underlying & Ultimate Layer / DSN-33)                |
|   - 最下層（Underlying）ベアメタル・x86-64 Linux ネイティブコード生成         |
|   - 64bit Tagged Pointer, バンプアロケータ, 末尾再帰 (TCO), フラットクロージャ|
|   - 外部依存ゼロのセルフホスティング (3-Stage Bootstrap 完全一致)             |
|   - 高速ネイティブ ELF 単一バイナリ出力 (GCC / GAS 連携)                      |
+===============================================================================+
```

### 1.2 ULisp のアイデンティティと責務

1. **Underlying（最下層・基底）**:
   Python や高級 VM を介さず、CPU レジスタ（`RAX`, `RSP`, `R12` 等）と OS のスタックフレームを直接制御する極限の低レイヤ層。
2. **Ultimate（究極・独立性）**:
   外部のいかなるランタイム（Python, Boehm GC, LLVM 等）にも依存せず、自分自身のソースコード（`compiler.scm`）を自分自身でコンパイルして完結する完全自律性。
3. **Unified Backend（ILisp AOT 昇格）**:
   セルフホスト完了後、ILisp の上位抽象（Scope Sets マクロやライブラリ構文）から脱糖された純粋 S 式を受け取り、瞬時に x86-64 アセンブリへと変換するネイティブバックエンドとして機能する。

---

## 2. アーキテクチャ基本設計とハードウェア・ABI 整合

### 2.1 64ビット Tagged Pointer メモリモデル

ULisp は 64 ビットアーキテクチャ（x86-64）を前提とし、ポインタ下位 2〜8 ビットを型タグとして利用する。

| 型 (Type) | ビットマスク / タグ | 内部表現 (Internal Bit Pattern) | 設計意図・最適化特性 |
| :--- | :--- | :--- | :--- |
| **Fixnum (小整数)** | 下位 2bit = `00` | `val << 2` (62bit 符号付き整数) | タグが `00` のため、加減算（`add`, `sub`）はシフト解除不要で直接実行可能。 |
| **Heap Pointer** | 下位 2bit = `01` | `(ptr & ~3) \| 0x01` | 8バイトアライメントされたヒープアドレスを指す。`Pair` や `Closure` に利用。 |
| **Character** | 下位 8bit = `0000_1110` (`0x0E`) | `(ascii_code << 8) \| 0x0E` | 文字リテラル。単項型述語 `char?` で高速判定。 |
| **Boolean** | 即値定数 | `#f`: `0x2F` (`0010_1111`)<br>`#t`: `0x6F` (`0110_1111`) | Scheme 仕様に基づき `#f` のみ偽、他はすべて真。`cmp rax, 0x2F` で判定。 |
| **Empty List (`'()`)** | 即値定数 | `'()`: `0x3F` (`0011_1111`) | リスト終端記号（NIL）。 |
| **Symbol Pointer** | 下位 2bit = `10` | `(sym_ptr & ~3) \| 0x02` | インターン済みシンボル構造体（名前文字列＋ハッシュ値）へのポインタ。 |

### 2.2 レジスタ割り当て・スタックフレーム・ABI 規約

* **RAX**: すべての式の評価結果が返却される主アキュムレータ。
* **RSP**: マシンスタックポインタ。
* **R12**: ヒープアロケーションポインタ（バンプアロケータの現在ポインタ）。
* **System V AMD64 ABI 整合と 16 バイトスタックアライメント**:
  - C ランタイム（`runtime.c` の `printf` や `exit`）を `call` する直前において、**`RSP` が必ず 16 バイト境界（`RSP % 16 == 0`）に整列**していることを保証する。
  - スタックフレーム確保時（`sub rsp, N`）は常にパディングを加え、未整列による SSE 命令（`movaps` 等）の `SIGSEGV` を物理遮断する。

### 2.3 ゼロGC・高速バンプアロケータ戦略

* コンパイラ自身のコンパイル実行（数千行のパースとコード生成）は、起動から数秒以内で完了するバッチ処理である。
* 複雑な GC（Mark-and-Sweep や Copying GC）の導入によるセルフホスト遅延を防ぐため、**「メモリ解放なしのバンプアロケータ（Bump Allocator）」** を採用する。
* 初期化時に `malloc(128 * 1024 * 1024)`（128MB）を確保し、`R12` レジスタを単調増加させる。Linux の仮想記憶機構（Demand Paging）により、実際に消費された物理メモリのみがコミットされる。

### 2.4 シンボル表現と決定論的インターン（Interning）テーブル

* コンパイラ自身は `(eq? (car expr) 'if)` や `(eq? (car expr) 'lambda)` のようにシンボル等値比較を膨大に行う。
* 文字列比較による低速化を防ぐため、コンパイル時および実行時ランタイムに**決定論的シンボルテーブル**を保持する。
* シンボルはインターン（一度出現した文字列は同一ポインタを共有）され、`eq?` は単なるポインタ比較（`cmp rax, rdx` / 1命令）で $O(1)$ 動作する。

---

## 3. 言語機能と低レイヤコード生成仕様

### 3.1 即値・単項演算・述語
* 整数リテラル `n` $\to$ `mov rax, (n << 2)`
* `(fxadd1 x)` $\to$ `add rax, 4`
* `(fixnum? x)` $\to$ `and al, 0x03` $\to$ `cmp al, 0` $\to$ `sete al` $\to$ フラグに応じて `#t` または `#f` を RAX へ。

### 3.2 局所変数 (`let`) とスタックマッピング
* コンパイル時環境（Compile-time Environment）として連想リスト `((var . stack_offset) ...)` を追跡。
* 変数束縛式を評価してスタック（`mov [rsp - offset], rax`）にプッシュし、本体式内で参照された場合は `mov rax, [rsp - offset]` でロード。

### 3.3 条件分岐 (`if`) と論理演算の脱糖
* `(if test then else)`:
  - `test` を評価し、`cmp rax, 0x2F`（`#f` と比較）。
  - 等しければ `.Lelse_XXX` へ `je`。
  - `then` 部を実行して `.Lend_XXX` へ `jmp`。
* `and`, `or`, `cond` は前処理パスで `if` 式の入れ子へと決定論的に脱糖（Desugar）。

### 3.4 ペアとリストプリミティブ (`cons`, `car`, `cdr`, `quote`)
* `(cons e1 e2)`:
  - `e1`, `e2` を順次評価してスタックに退避。
  - バンプポインタ `R12` から 16 バイトを確保し、`[r12]` に `e1`、`[r12 + 8]` に `e2` を格納。
  - `lea rax, [r12 + 1]`（タグ `0x01` を付与）を RAX にセットし、`add r12, 16`。
* `(car p)` / `(cdr p)`: タグ `0x01` を解除（`mov rdx, [rax - 1]` / `mov rdx, [rax + 7]`）してロード。

### 3.5 末尾呼び出し最適化 (Tail Call Optimization: TCO)
* **Scheme の生命線**: ループ構文（`while`/`for`）を持たないため、再帰呼び出しがスタックを消費しないことが絶対条件。
* 末尾位置（Tail Position）にある関数呼び出しにおいて、新しいスタックフレームを作らず、**現在のスタックフレームの引数スロットを上書きして対象ラベルへ直接 `jmp`** する。

### 3.6 第一級関数とフラットクロージャ (Flat Closures)
* `(lambda (x ...) body ...)`:
  - 静的自由変数解析（Free Variable Analysis）を実行し、外部スコープからキャプチャすべき変数を抽出。
  - ヒープ上にフラットクロージャオブジェクト `[コードアドレス, キャプチャ変数1, キャプチャ変数2, ...]` を生成（タグ `0x01`）。
  - 間接関数呼び出し時、クロージャポインタを特定レジスタ（例: `RBX`）に保持したままコードアドレスを取り出して `call rbx`（または末尾 `jmp`）し、関数内部からは `RBX` 経由でキャプチャ変数を参照。

### 3.7 手書き再帰下降 S式リーダー (`read`) とシステムコール I/O
* 外部ライブラリを完全排除するため、Scheme 自身で記述された極小の再帰下降 S式リーダーを搭載。
* Linux システムコール（`sys_read` = 0, `sys_write` = 1）または C ランタイムの `getchar` / `putchar` を直接バインドし、`read-char`, `write-char`, `peek-char` から `read` を構築。

---

## 4. インクリメンタル開発ロードマップ (全7フェーズ・27ステップ)

植山類氏の *compilerbook* 手法を忠実に踏襲し、1ステップごとにアセンブリ出力・実行・アサーションを行う自動テストをパスさせてコミットを刻む。

```
[Phase 1: 即値・単項演算] ──▶ [Phase 2: スタック・let] ──▶ [Phase 3: 分岐・述語]
       │                             │                             │
       ▼                             ▼                             ▼
  Step 1: 42                    Step 5: (+ e1 e2)             Step 9: (if ...)
  Step 2: #t, #f, '(), #\a      Step 6: 多項・比較演算         Step 10: and, or 脱糖
  Step 3: fxadd1, fxsub1        Step 7: let 局所変数          Step 11: begin 複文
  Step 4: fixnum?, null?        Step 8: 変数シャドウイング

       ┌─────────────────────────────┬─────────────────────────────┘
       ▼                             ▼
[Phase 4: ヒープ・リスト]     [Phase 5: 手続き・TCO・クロージャ]
  Step 12: バンプアロケータ       Step 17: define トップレベル手続き
  Step 13: cons, car, cdr        Step 18: TCO (末尾呼び出し最適化)
  Step 14: set-car!, set-cdr!    Step 19: 自由変数静的解析
  Step 15: quote 構文            Step 20: lambda フラットクロージャ
  Step 16: シンボルインターン

       ┌─────────────────────────────┘
       ▼
[Phase 6: 自前リーダー・最小 I/O] ──▶ [Phase 7: セルフホスティング検証]
  Step 21: read-char, write-char         Step 25: Stage 1 バイナリ生成 (ILisp 経由)
  Step 22: 自前 S式 read 実装             Step 26: Stage 2 バイナリ生成 (自前 Stage 1 経由)
  Step 23: 構文脱糖パス (cond, let*)      Step 27: 固定点検証 (Stage 2 vs Stage 3 完全一致)
  Step 24: compiler.scm リファクタリング
```

---

## 5. 3段階セルフホスティングブートストラップ連鎖と不動点検証

### 5.1 ブートストラップ連鎖 (Stage 1 〜 Stage 3)

```
                       [ compiler.scm (自作ソースコード) ]
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
       【 Stage 1 ブート 】                          【 Stage 2 生成 】
python3 -m ilisp compiler.scm < compiler.scm > stage1.s   ./scheme-stage1 < compiler.scm > stage2.s
gcc -o scheme-stage1 runtime.o stage1.s                   gcc -o scheme-stage2 runtime.o stage2.s
                │                                             │
                └──────────────────────┬──────────────────────┘
                                       ▼
                             【 Stage 3 生成 ＆ 固定点検証 】
                      ./scheme-stage2 < compiler.scm > stage3.s
                      cmp stage2.s stage3.s  ===> 差分ゼロ (100% 一致)
```

1. **Stage 1**: ILisp（プロジェクト標準の R7RS 準拠処理系 `python3 -m ilisp`）上で `compiler.scm` を実行し、自分自身をコンパイルして `stage1.s` を生成。`gcc` でリンクして実行可能バイナリ `scheme-stage1` を作成。
2. **Stage 2**: ネイティブバイナリ `scheme-stage1` を実行し、再度 `compiler.scm` をコンパイルして `stage2.s` を生成。リンクして `scheme-stage2` を作成。
3. **Stage 3 ＆ 不動点検証 (Fixed-Point Verification)**:
   `scheme-stage2` で `compiler.scm` をコンパイルして `stage3.s` を生成。
   `diff stage2.s stage3.s` を実行し、**アセンブリ出力が 1 バイトの狂いもなく完全一致（差分ゼロ）** することを確認する。

### 5.2 決定論的コード生成と完全一致検証 (`diff` ゼロ保証)

* セルフホスト検証で差分が生じる原因（ハッシュテーブル走査順の非決定性、ポインタ値の直接文字列化など）を徹底排除する。
* ラベル命名カウンタ（`.L1`, `.L2`）および環境リスト走査は、常に出現順序に従う決定論的アルゴリズムを採用する。

---

## 6. ILisp AOT バックエンド統合仕様 (DSN-31 Backend B への昇格)

ULisp のセルフホスティング達成後、本コンパイラは **ILisp (DSN-31) の「Backend B: Native AOT コンパイラ」** としてプラットフォームに統合される。

### 6.1 統合アーキテクチャと依存性境界

```
    [ ILisp / ALisp ソースコード (.ilisp) ]
                       │
                       ▼
    [ ILisp Scope Sets マクロ展開器 (ilisp/syntax.py) ]
                       │ (純粋 Kernel S式 AST に脱糖)
                       ▼
    [ ILisp ULisp Codegen ブリッジ (ilisp/backend/ulisp_codegen/) ]
                       │
                       ▼
    [ ULisp ネイティブ AOT コンパイラ (ulisp/compiler.scm / binary) ]
                       │
                       ▼
    [ x86-64 アセンブリ (.s) ──▶ GAS / GCC ──▶ スタンドアロン ELF 単一バイナリ ]
```

### 6.2 ILisp S式 AST から ULisp 入力へのコンパイルパイプライン

1. **マクロ脱糖**: ILisp の高度な Scope Sets 衛生的マクロ（`syntax-rules`）、モジュール定義（`define-library`）、ALisp の契約構文（`define/c`）は、ILisp 側で純粋な Scheme コア形式（`lambda`, `if`, `let`, `set!`）に脱糖される。
2. **ULisp へのパイプライン投入**: 脱糖された純粋 S 式ストリームを ULisp コンパイラに入力する。
3. **ネイティブバイナリ出力**: ULisp が最適化された x86-64 アセンブリを生成し、`gcc` / `clang` を経由してホスト環境のネイティブ ELF バイナリを直接出力する。

### 6.3 ランタイム共有とネイティブ ELF 単一バイナリ生成

* ILisp の Python ゼロコピー相互運用を必要としない純粋計算・バッチ処理・記号推論コードは、ULisp を通じて Python 依存ゼロの単一バイナリとして配布・実行可能となる。
* 起動時間は 0.1ms 未満、メモリフットプリントは数MB以下という極限のパフォーマンスを達成する。

---

## 7. ディレクトリ構成と開発運用プロトコル

### 7.1 初期プロジェクトツリー (`ulisp/`)

本リポジトリ内の独立サンドボックス、または独立リポジトリとして以下の構成で開始する：

```text
ulisp/
├── Makefile          # compilerbook 準拠のテスト・ビルド自動化
├── compiler.scm      # ULisp コンパイラ本体 (ILisp およびネイティブ ULisp 上で動作する自己充足的 Scheme スクリプト)
├── lib/              # Scheme 自前標準ライブラリ
│   ├── string.scm    # 文字列・数値変換, シンボル管理 (string->symbol, symbol->string, number->string)
│   ├── printer.scm   # Scheme 出力フォーマッタ (display, write, newline)
│   └── reader.scm    # 手書き再帰下降 S 式リーダー (read)
├── runtime.c         # Thin Debug Runtime (SIGSEGV backtrace, 1GB バンプアロケータ, 最小 3 I/O primitives)
├── test.sh           # インクリメンタル自動テストランナー
├── bootstrap.sh      # 3段階ブートストラップ実行 ＆ 固定点検証スクリプト
└── README.md         # プロジェクト仕様とステップ進行ログ
```

### 7.2 開発運用プロトコル

1. **コミット粒度**: 1 ステップ（または 1 プリミティブ追加）ごとに 1 コミット。コミットメッセージにはテストケースの入出力（例: `feat: compile (+ 1 2) to x86-64 add`）を明記。
2. **グリーン維持**: すべてのコミットで `./test.sh` が全件パス（PASS）していることを義務付ける。

---

## 8. 品質ゲート・テスト自動化

| テストスイート | 実行コマンド | 合格基準 (Gate Criteria) |
| :--- | :--- | :--- |
| **ユニット機能テスト** | `./test.sh` | Phase 1〜6 の全ステップ（即値・演算・分岐・リスト・クロージャ・I/O）100% PASS |
| **TCO 深度テスト** | `./test.sh tco` | 100万回以上の末尾再帰がスタックオーバーフロー（SIGSEGV）を起こさず完走 |
| **メモリ健全性テスト** | `valgrind ./tmp` | アライメント不正、不正領域アクセス（Crash）ゼロ件 |
| **セルフホスト固定点テスト**| `./bootstrap.sh` | `diff stage2.s stage3.s` が終了コード 0（完全一致・差分ゼロ） |

---

## 9. 結論と移行計画

本 [DSN-33] 仕様書の承認により、**「ALisp（エージェント）── ILisp（インフラ）── ULisp（アンダーライング/最底層）」** の三層垂直統合アーキテクチャが完成した。

まずは Phase 1（Step 1: 整数 `42` のコンパイル）から独立サンドボックスにて着手し、Step 27（セルフホスティング固定点検証）の達成をもって ULisp を ILisp の公式 AOT コンパイラバックエンドへと正式編入する。

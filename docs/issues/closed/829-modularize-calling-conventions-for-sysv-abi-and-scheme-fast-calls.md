---
ID: 829
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [FEAT] 呼出規約 (Calling Convention) の多重化・モジュール分離とゼロオーバーヘッド C-FFI の実現 (ID: 829)

## 1. 概要 / Summary
現在、ULisp コンパイラおよび低レベル中間表現（LIR）における関数呼出・引数渡し処理は、Pass 124 (`124_lir_call_abi.scm`) および x86_64 バックエンド (`140_backend_x86_64.scm`) 内に Scheme 内部専用の固定ロジック（GPR レジスタ `rdi..r9` + `%rax` への引数個数タグ設定 + `%r10` クロージャポインタ渡し）としてモノリシックに埋め込まれている。

本 Issue では、呼出規約（Calling Convention）の決定と引数・戻り値の物理配置（ABI レイアウト計算）を独立した抽象化モジュール `calling_convention.scm` として分離・多重化する。これにより以下の呼出規約を直交して扱えるアーキテクチャを確立する：
1. **Scheme 高速内部規約 (`scheme-fast`)**:
   - 汎用レジスタ渡し（`%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`）
   - クロージャポインタ `%r10`、引数個数タグ `%rax`
   - スタックマップによる GC セーフポイント追跡
   - 引数個数一致時の末尾呼出最適化（TCO）
2. **System V AMD64 ABI 規約 (`sysv-abi`)**:
   - 整数・ポインタ引数のレジスタ渡し（`%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`）
   - 浮動小数点引数の XMM レジスタ渡し（`%xmm0` 〜 `%xmm7`）
   - 第 7 引数以降の 8 バイトスタック渡し（右から左へ配置）
   - **`call` 発行直前における 16 バイトスタックアライメント厳密保証**
   - **可変長引数（Varargs: `printf` 等）における `%al` レジスタへの XMM レジスタ使用個数（0〜8）設定**
   - Callee-Saved レジスタ退避、および Scheme ナーサリヒープポインタ `%r12` の保全
   - 戻り値の型別配置（整数: `%rax`, 浮動小数点: `%xmm0`）
3. **将来拡張性（AAPCS64 / Cdecl）**:
   - AArch64 標準 ABI (`x0..x7`, `v0..v7`) やその他規約へのプラグイン拡張基盤

これにより、Scheme から外部 C ライブラリ（libc/musl の `printf`, `puts`, `sin`, `cos`, `malloc`, `free` 等）をトランポリンなしで直接呼び出す**ゼロオーバーヘッド C-FFI** を実現し、DSN-38 C コンパイラフロントエンドとのシームレスな相互運用基盤を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-38 仕様書**: §2 (C2: SysV ABI, E5: SysV 準拠呼出/入口/出口, E6: 関数ポインタ間接呼出)
- **DSN-33 仕様書**: §2.1 (Tagged Pointer メモリモデル), §3.3 (LIR 最適化・コード生成パイプライン)
- **DSN-33-02 仕様書**: §4.3 (機械型と幅指定操作), §5.1 (呼出規約と外部関数インターフェース)
- **関連 Issue**:
  - #810: セーフポイント除外規則およびトリビアルアクセサ間引き
  - #826: 機械型 (i8..i64, f32, f64, ptr) を備えた Typed LIR への移行
  - #828: LIR におけるオーバーフロー検知付き算術および符号なし演算オペコードの新設
  - #831: 160 Portable C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期
  - #838: レジスタ制約付きインライン・アセンブリ (%inline-asm) の LIR 統合

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/compiler/calling_convention.scm](../../ulisp/compiler/calling_convention.scm): 呼出規約の抽象データ構造、ABIInfo ディスパッチャ、引数レイアウト計算（新規作成）
- [ ] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm): LIR 関数属性（`(:calling-convention <conv>)`, `(:varargs #t/#f)`, `(:return-type <type>)`）および C-FFI 呼出構文定義
- [ ] [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm): 呼出規約・スタック整列・レジスタ型制約（GPR/XMM）の静的検証
- [ ] [ulisp/lir/124_lir_call_abi.scm](../../ulisp/lir/124_lir_call_abi.scm): `calling_convention.scm` と連携したモジュール式引数配置・16バイトアライメント計算へのリファクタリング
- [ ] [ulisp/lir/130_lir.scm](../../ulisp/lir/130_lir.scm): 関数定義・呼出ノードにおける規約属性の伝播
- [ ] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm): SysV ABI 準拠の呼出生成、16バイト境界整列、`%al` 設定、および `%r12` ヒープポインタ保全
- [ ] [ulisp/backend/150_backend_aarch64.scm](../../ulisp/backend/150_backend_aarch64.scm): AAPCS64 呼出規約への対応
- [ ] [ulisp/backend/160_backend_c.scm](../../ulisp/backend/160_backend_c.scm): C バックエンドにおける標準 C 関数呼出への直接 Lowering
- [ ] [ulisp/Makefile](../../ulisp/Makefile): `calling_convention.scm` の組み込みおよび `test_sysv_abi_calls` ターゲット追加
- [ ] [ulisp/tests/test_sysv_abi_calls.scm](../../ulisp/tests/test_sysv_abi_calls.scm): SysV 相互呼出（整数/ポインタ/浮動小数点/スタックスピル/可変長）単体・結合テストスイート（新規作成）

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)
- **CWE-119 / CWE-120 (Buffer Misalignment & Stack Overflow / Corruption)**:
  - System V AMD64 ABI において、`call` 命令発行時点でスタックポインタ `%rsp` が 16 バイト境界に整列されていない場合、libc（`printf`, `puts`, `memcpy` 等）内部で使用される SSE/AVX ベクトル命令（`movaps` 等）がハードウェア例外（General Protection Fault `#GP`, SIGSEGV）を発生させる。
  - **対策**: `calling_convention.scm` において、スピル引数のバイト数および既存フレーム深度から必要なパディングバイト数（0 または 8 バイト）を厳密に計算し、`call` 直前のスタックが `(%rsp + 8) % 16 == 0`（`call` 後の callee 入口で `%rsp % 16 == 0`）となるよう自動調整する。
- **CWE-686 (Function Call With Incorrect Signature / Type Confusion)**:
  - 浮動小数点数を GPR（`%rdi` 等）に渡したり、整数を XMM レジスタに渡すことで、外部 C 関数で予期せぬ値の解釈やメモリアクセス違反が生じる。
  - **対策**: Typed LIR 型情報（`i64`, `f64`, `ptr`）に基づき、GPR 用レジスタリスト（`%rdi`..`%r9`）と XMM 用レジスタリスト（`%xmm0`..`%xmm7`）を完全に分離して独立に割り当てる。`lir_verifier.scm` にてオペランド型とターゲットレジスタクラスの一致を厳格に検証する。
- **CWE-465 (Nursery Heap Pointer / Register State Corruption by Callee)**:
  - ULisp ランタイムは、高速アロケーションのために `%r12` を Scheme ナーサリヒープポインタとして占有している。System V ABI では `%r12` は callee-saved レジスタと規定されているが、外部の C 関数やアセンブリルーチンが不用意に `%r12` を改変した場合、Scheme のヒープアロケータ全体が破壊される。
  - **対策**: 外部 C-FFI 境界呼出（`%call-foreign`）の前後において、`%r12` の整合性を防御的ガード（必要に応じてスタック退避・復元、またはアサートチェック）する機構を導入する。
- **CWE-843 (Varargs Register Misbehavior & `%al` Register Undefined State)**:
  - System V AMD64 ABI の可変長引数（Varargs: `printf`, `sprintf` 等）では、レジスタ `%al` に「引数として渡されたベクトル/浮動小数点レジスタの個数（0〜8）」が格納されていなければならない。`%al` が不正な値の場合、libc が不正なスタック領域に XMM をダンプしてクラッシュする。
  - **対策**: Varargs 呼び出し時、ABI レイアウト計算器が XMM 引数の使用個数を集計し、バックエンドが確実に `mov al, <num_xmm>`（浮動小数点がなければ `xor eax, eax`）を発行する。
- **純粋 Scheme (Zero External / Gauche Dependency)**:
  - 全コードを純粋な R7RS / ULisp S式構文で完結させ、外部依存を一切排除する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `feat/829-modular-calling-conventions-sysv-abi`

### ステップ 1: `ulisp/compiler/calling_convention.scm` の設計と実装
1. 呼出規約レコードおよび型定義：
   - 規約識別子: `'scheme-fast`, `'sysv-abi`, `'aapcs64`
   - 引数記述レコード: `(make-arg-desc type index)`
   - 配置先レコード: `(make-arg-loc kind target offset)` （`kind`: `'reg`, `'xmm`, `'stack`）
2. レイアウト計算関数 `compute-call-abi-layout`:
   - 入力: `convention`, `arg-types`（例: `'(ptr i64 f64 f64)`）, `varargs?`
   - 出力: `(values locations total-stack-bytes padding-bytes num-gpr num-xmm)`
   - **`sysv-abi` ロジック**:
     - GPR リスト: `(%rdi %rsi %rdx %rcx %r8 %r9)` （最大 6 個）
     - XMM リスト: `(%xmm0 %xmm1 %xmm2 %xmm3 %xmm4 %xmm5 %xmm6 %xmm7)` （最大 8 個）
     - レジスタ枯渇分はスタックスロット（`offset: 0, 8, 16...`）へ順次割り当て。
     - 全スタック引数サイズに 16 バイト境界調整パディングを計算。

### ステップ 2: LIR 構文 (`lir_lang.scm`) および検証器 (`lir_verifier.scm`) の拡張
1. `%lir-function` 属性拡張:
   - `(%lir-function name ((:calling-convention <conv>) (:return-type <type>) ...) body)`
2. 外部関数呼出ノード新設:
   - `(%call-foreign fn-name calling-conv ret-type args-with-types frame-shift safepoint-lbl)`
   - または拡張 `%c-call`: `(%c-call fn-name frame-shift (:abi 'sysv) (:varargs #t) (:xmm-count n))`
3. `lir_verifier.scm` における静的検証:
   - 規約ごとの許可レジスタ整合性検証。
   - `frame-shift` が 16 の倍数（リターンアドレス 8 バイトと合わせて 16 バイト整列）であることの検証。

### ステップ 3: LIR Call ABI パス (`124_lir_call_abi.scm`) のリファクタリング
1. 既存の Scheme 呼出ロジックを `calling_convention.scm` の `'scheme-fast` 規約を利用する構造へリファクタリング。
2. 外部呼出（`%c-call` / `%call-foreign`）処理関数 `lir-compile-foreign-call` を新設:
   - 引数型リストから `compute-call-abi-layout` を呼び出し、各引数の評価順序および一時スタックスロットへの配置を制御。
   - 16 バイトスタックアライメントを保証する `frame-shift` を自動算出。
   - レジスタへのロード（GPR および XMM）およびスタックスピル引数のコピー命令列を生成。

### ステップ 4: x86_64 バックエンド (`140_backend_x86_64.scm`) のコード生成
1. SysV 呼出命令の生成:
   - 16 バイトアライメント調整用 `sub rsp, <shift>`
   - Varargs フラグが有効な場合、`mov al, <num_xmm>`（XMM 未使用時は `xor eax, eax`）を発行。
   - 外部シンボル（`call <c-fn>`）の発行。
   - スタック復元 `add rsp, <shift>`。
2. レジスタ保全:
   - 必要に応じて `%r12`（Scheme ナーサリポインタ）の保護。
3. 関数エントリ（将来の C 互換 Scheme 関数エクスポート）:
   - `(:calling-convention 'sysv-abi)` を持つ関数のプロローグにおいて、SysV レジスタから引数を取得し、標準スタックフレームを構築するコード生成。

### ステップ 5: Portable C (`160_backend_c.scm`) および AArch64 (`150_backend_aarch64.scm`) の対応
1. C バックエンド:
   - 外部 C 関数呼出を純粋な C 関数呼出構文 `res = fn(arg1, arg2);` にマップ。
2. AArch64 バックエンド:
   - AAPCS64 レイアウト（`x0..x7`, `v0..v7`, スタック 16 バイト整列）の適用。

### ステップ 6: テストスイートの作成と統合検証
1. `ulisp/tests/test_sysv_abi_calls.scm`:
   - Group 1: 規約抽象レイアウト計算ユニットテスト（引数割り当て、スタックオフセット、パディング計算）
   - Group 2: GPR 整数引数（1〜6 引数）の libc `puts` / `exit` 呼出検証
   - Group 3: 7 引数以上のスタックスピル引数呼出検証
   - Group 4: XMM 浮動小数点引数呼出検証（`sin`, `cos` 等）
   - Group 5: 可変長引数 `printf` 呼出検証（整数・文字列・浮動小数点混合、`%al` 設定確認）
   - Group 6: 16 バイトスタックアライメント境界整合性検証
2. `ulisp/Makefile` に `COMPILER_BASE` への `compiler/calling_convention.scm` 追加および `test_sysv_abi_calls` ターゲット登録。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/compiler/calling_convention.scm` が実装され、`scheme-fast` および `sysv-abi` の引数・スタックレイアウトが純粋 Scheme で正確に算出できること。
- [x] S式括弧チェック (`python3 scripts/lint_sexpr.py`) が新設・変更ファイルすべてで PASS（バランス保証）すること。
- [x] `124_lir_call_abi.scm` および `140_backend_x86_64.scm` がリファクタリングされ、16 バイトスタック境界整列と `%al` 設定が保証されること。
- [x] Scheme から `puts` および可変長 `printf` 等の SysV C 関数を直接呼び出し、クラッシュなく正確に出力・復帰できること。
- [x] 単体・結合テストスイート `test_sysv_abi_calls.scm` が 100% PASS すること。
- [x] `make -C ulisp build/ulisp-modular`、`make -C ulisp bootstrap`、`make -C ulisp test` の全ビルド・テストがエラー・警告 0 件で通過すること。

---
ID: 593
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT/ENH] LIR層: define-language L_lir_canonical の導入と lir_verifier 宣言的統合 (ID: 593)

## 1. 概要 / Summary
Issue 589（Canonical LIR 境界の確立）および Issue 590（物理層分離）により LIR 層が独立したが、現在の LIR 境界検証（`ulisp/lir/lir_verifier.scm`）は約 550 行の手続き型コードでハードコードされており、DSL（Nanopass Framework）の `define-language` による形式文法定義が存在しない。
これにより、LIR の構文仕様の変更とバリデータの挙動に乖離（Spec Drift）が発生するリスクがある。

本 Issue では、LIR 層の正典表現を Nanopass DSL として形式化した `define-language L_lir_canonical` を定義し、`lir/lir_verifier.scm` の判定ロジックと宣言的に統合・同期させる。これにより、LIR 境界における AST 検証を機械的に担保し、フロントエンドとバックエンドの境界契約（Contract）を宣言的かつ堅牢に確立する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/pipeline_architecture.md)
  - [LIR 命令セット仕様書](../../ulisp/docs/lir_specification.md)
- **関連 Issue**:
  - Issue 589: Canonical LIR 境界の確立
  - Issue 590: 3層物理ディレクトリ分離
  - Issue 591: コンパイラドライバおよびテストスイートの階層化（LIR中間出力モード `--target-lir`）
  - 依存 Issue: なし（本ロードマップの第1ステップ）

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lir/lir_lang.scm](../../ulisp/lir/lir_lang.scm) (新規: `L_lir_canonical` の形式言語定義・述語エクスポート)
- [x] [ulisp/lir/lir_verifier.scm](../../ulisp/lir/lir_verifier.scm) (`L_lir_canonical` による Tier 1 構文検証と Tier 2 意味論的検証の統合)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`LIR_PASSES` への `lir/lir_lang.scm` 追加およびビルドルール整合化)
- [x] [ulisp/tests/test_lir_verifier.scm](../../ulisp/tests/test_lir_verifier.scm) (`L_lir_canonical?` および文法不整合検出の単体テスト拡充)
- [x] [ulisp/docs/lir_specification.md](../../ulisp/docs/lir_specification.md) (仕様書内の文法定義と実装コードの整合性更新)
- [x] [ulisp/docs/pipeline_architecture.md](../../ulisp/docs/pipeline_architecture.md) (LIR 言語階層図の更新)

---

## 3.2 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

LIR は、高水準 Scheme の安全な抽象構文木から、メモリを直接操作する低水準マシン語生成層（x86-64 / AArch64 / C99）への境界に位置する。不正な LIR や仕様外 AST が通過した場合の脅威を以下の通り特定し、対策を講じる。

| 脅威分類 (STRIDE / CWE) | 脅威シナリオ | 影響度 | 対策要件 (Mitigation) |
| :--- | :--- | :---: | :--- |
| **不正入力検証不備 (CWE-20)** | フロントエンドのバグや未脱糖構文が漏洩し、未定義オペコードや不正オペランドがバックエンドに渡る。 | High | `L_lir_canonical` による厳格なスキーマ検証を第1防壁とし、未定義オペコード・型不整合を即時検知してコンパイルを中断（Fail-Fast）。 |
| **メモリ破壊・境界外アクセス (CWE-119 / CWE-787)** | 不正なスタックスロット番号、アライメント未調整の frame-size、あるいは不正レジスタ指定により、生成バイナリ実行時にスタック破壊や SEGV が発生する。 | Critical | 形式文法でのオペランド型強制に加え、`validate-lir` において 8 バイト境界アライメントおよびスタックマップビットマップの正当性を二重検証する。 |
| **制御フローハイジャック (CWE-674 / CWE-400)** | 未定義ラベルへのジャンプや引数個数不整合によるスタック不整合、あるいは循環ブロックによる検証時の再帰スタック枯渇。 | High | 線形走査によるラベル一意性検査、ブロック引数 arity 検証、および深さ制限・ループ検出を検証器で担保する。 |

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/593-define-lir-canonical-language-and-verifier-integration`

### 4.1 `L_lir_canonical` の文法定義策定 (`ulisp/lir/lir_lang.scm`)
Nanopass Framework DSL（`ulisp/compiler/nanopass.scm`）の `define-language` を用いて、Canonical LIR の形式言語 `L_lir_canonical` を定義する。

1. **Terminals**:
   - `(symbol (x lbl var cond_op sp_lbl))`
   - `(integer (n offset shift frame_size bytes tag si cnt bitmap))`
   - `(string (str fn_name))`
2. **Nonterminals**:
   - `Register`:
     - `%rax`, `%rbx`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%rbp`, `%rsp`
     - `%r8`, `%r9`, `%r10`, `%r11`, `%r12`, `%r13`, `%r14`, `%r15`, `%al`
     - `(%reg x)`
   - `StackSlot`: `(%stack offset)`
   - `MemRef`: `(%mem reg offset)`
   - `LValue`: `reg`, `stack_slot`, `mem_ref`, `var`
   - `Operand`: `lval`, `n`, `lbl`
   - `Inst`:
     - **制御フロー**: `(%label lbl)`, `(%block lbl (x ...) inst ...)`, `(%jump lbl)`, `(%jump lbl (opnd ...))`, `(%jump-if-false reg lbl)`, `(%jump-if-false reg lbl (opnd ...))`, `(%jump-if reg lbl1 (opnd1 ...) lbl2 (opnd2 ...))`, `(%jump-cond cond_op lbl)`, `(%jump-if-zero lbl)`, `(%direct-jump lbl)`, `(%return)`, `(%return opnd)`
     - **呼出・ABI**: `(%c-call fn_name shift)`, `(%call-closure shift)`, `(%call-closure shift sp_lbl)`, `(%direct-call lbl shift)`, `(%direct-call lbl shift sp_lbl)`, `(%dispatch-consumer si1 si2 shift)`
     - **メモリ・転送**: `(%mov lval opnd)`, `(%load reg1 reg2 offset)`, `(%store reg1 offset opnd)`, `(%load-byte-zx reg1 reg2 offset)`, `(%store-byte reg1 offset opnd)`, `(%push reg)`, `(%pop reg)`, `(%code-ref reg lbl)`, `(%str-ref reg lbl)`, `(%global-ref reg var)`, `(%global-set! var reg)`
     - **算術・論理**: `(%add opnd1 opnd2)`, `(%raw-add opnd1 opnd2)`, `(%sub opnd1 opnd2)`, `(%raw-sub opnd1 opnd2)`, `(%imul opnd1 opnd2)`, `(%raw-mul opnd1 opnd2)`, `(%neg opnd)`, `(%inc opnd)`, `(%cqo)`, `(%idiv opnd)`, `(%shl opnd shift)`, `(%shr opnd shift)`, `(%sar opnd shift)`, `(%bit-and opnd1 opnd2)`, `(%bit-or opnd1 opnd2)`, `(%bit-xor opnd1 opnd2)`, `(%cmp opnd1 opnd2)`, `(%raw-cmp opnd1 opnd2)`, `(%set-boolean opnd cond_op)`, `(%box-fixnum opnd1 opnd2)`, `(%unbox-fixnum opnd1 opnd2)`, `(%syscall)`
     - **ランタイム・GC・例外**: `(%alloc opnd bytes tag)`, `(%alloc opnd bytes tag si)`, `(%alloc-stack opnd offset tag)`, `(%capture-cc lbl si)`, `(%push-handler lbl si1 si2)`, `(%pop-handler si)`, `(%raise)`, `(%set-values-count cnt)`, `(%store-values-buf si cnt)`
   - `StringEntry`: `(lbl str)`
   - `SafepointEntry`: `(lbl frame_size bitmap)`
   - `FunctionDecl`: `(%lir-function lbl (params (x ...)) (frame-size frame_size) (body inst ...))`
   - `MainDecl`: `(%lir-main (frame-size frame_size) (body inst ...))`
   - `Program` (エントリ Nonterminal):
     - `(%lir-program (strings (se ...)) (stackmaps (sm ...)) (%lir-functions f ...) m)`

### 4.2 `lir_verifier.scm` との統合アーキテクチャ
2段階の多層防護（Two-Tier Verification）アーキテクチャを導入する：
- **Tier 1 (構文的・スキーマ検証)**:
  - `(L_lir_canonical? prog)` または `(nanopass-ast-valid? 'L_lir_canonical prog)` を第1段ゲートとして実行。
  - 不正な構造、未定義オペコード、文法外の引数リストを即時に検出。
- **Tier 2 (意味論的・コンテキスト不変条件検証)**:
  - 既存の `lir_verifier.scm` の意味論的チェック（CFG ラベル重複排除、到達可能ラベルの存在検査、ブロック引数とジャンプ実引数の arity 一致、スタックフレームの 8 バイトアライメント、Safepoint スタックマップのビットマップ正当性）を連動実行。
  - レジスタやオペランドの基本バリデーション述語（`lir-valid-register?`, `lir-valid-operand?`）を `L_lir_canonical` の文法定義と整合化。

### 4.3 `ulisp/Makefile` の更新
- `LIR_PASSES` 変数において、`lir/lir_verifier.scm` の直前に `lir/lir_lang.scm` を配置する。
- これにより、`compiler.scm` 生成時および `build/compiler_passes.scm` 生成時に自動的に `L_lir_canonical` がロードされ、自己ホストブートストラップおよび単体テスト環境で利用可能となる。

### 4.4 テストケース拡充方針 (`ulisp/tests/test_lir_verifier.scm`)
1. **L_lir_canonical 述語テスト**:
   - `(L_lir_canonical? <valid-lir>)` が `#t` を返すことの確認。
   - 各種正当な命令形式（制御、ABI、メモリ、算術、ランタイム）の認識テスト。
2. **文法外・不正 AST の拒絶テスト**:
   - 未定義オペコード（`(%unknown-op ...)`）の確実な拒絶。
   - 不正なオペランド構造（即値位置への不正シンボル等）の拒絶。
   - 壊れた `%lir-program` ルート構造の拒絶。
3. **リグレッション検証**:
   - 既存の 27 テストケースがすべて引き続き PASS すること。
   - `bash ulisp/test_lir.sh`（9ケース）がすべて PASS すること。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/lir/lir_lang.scm` が作成され、`define-language L_lir_canonical` および述語 `L_lir_canonical?` が定義されていること。
- [x] `ulisp/Makefile` の `LIR_PASSES` に `lir/lir_lang.scm` が登録され、`compiler.scm` のビルドが成功すること。
- [x] `ulisp/lir/lir_verifier.scm` が `L_lir_canonical?` を活用し、構文検証と意味論検証が協調動作すること。
- [x] `ulisp/tests/test_lir_verifier.scm` に `L_lir_canonical` 単体テストが追加され、全テストが 100% PASS すること。
- [x] `bash ulisp/test_lir.sh` によるフロントエンド LIR 生成テスト（9/9）が 100% PASS すること。
- [x] `make -C ulisp test_nanopass` が 100% PASS すること。
- [x] コードベース全体で絶対パス参照が存在しないこと（プロジェクト規則準拠）。

---

## 6. 検証手順 / Verification Procedures
1. **コンパイラパス再生成と静的検証**:
   ```bash
   make -C ulisp compiler
   make -C ulisp build/compiler_passes.scm
   ```
2. **LIR Verifier 単体テスト実行**:
   ```bash
   make -C ulisp test_lir_verifier
   ```
3. **Frontend LIR 中間出力回帰テスト実行**:
   ```bash
   bash ulisp/test_lir.sh
   ```
4. **Nanopass フレームワーク全体テスト実行**:
   ```bash
   make -C ulisp test_nanopass
   ```
5. **品質ゲート全検証**:
   ```bash
   make static_analysis
   ```


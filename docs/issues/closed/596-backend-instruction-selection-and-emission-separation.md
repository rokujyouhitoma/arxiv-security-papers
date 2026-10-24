---
ID: 596
種別: Feature
優先度: Medium
ステータス: Closed (Completed)
---

# [FEAT/ENH] Backend層: define-language L_asm 導入による命令選択とコード生成の2段階分離 (ID: 596)

## 1. 概要 / Summary
現在の ULisp バックエンド（`backend/140_backend_x86_64.scm`, `backend/150_backend_aarch64.scm`, `backend/160_backend_c.scm`）は、LIR 命令を受け取って直接文字列（GNU アセンブリ形式または C99 ソーステキスト）を組み立てて出力している。
この一枚岩（Monolithic）の構成には以下の重大なアーキテクチャ上の課題が存在する：
1. **ターゲット依存のピープホール最適化が困難**: 文字列化された後に命令の融合や冗長命令削除を行うのは正規表現やテキスト処理に頼らざるを得ず極めて脆弱。
2. **網羅性検証・型安全性の欠如**: LIR の全命令・オペランド形式がターゲット機械語へ正しくマップされているか、AST レベルで Nanopass Verifier やスキーマ検証を適用できない。
3. **命令選択（Instruction Selection）とコード整形の結合**: レジスタ割付済み LIR から機械語オペコードへのマッピング責務と、アラインメント・ディレクティブ・コメント等のテキストシリアライズ責務が密結合している。

本 Issue では、各バックエンドにターゲット命令を抽象化した `define-language L_asm_x86` を導入し、**「命令選択（Instruction Selection: LIR → L_asm）」** と **「コード出力（Code Emission / Unparser: L_asm → テキスト）」** の 2 段階分離を実現する。
さらに、中間 AST `L_asm_x86` を介した機械語ピープホール最適化パス（`143_backend_x86_peephole.scm`）を新設し、ゼロクリアの `xor` 化や冗長 move 削除などのターゲット固有最適化を安全に適用する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [ULisp パイプライン・Nanopass 詳細仕様書](../../ulisp/docs/spec_pipeline.md)
- **関連 Issue**:
  - Issue 569: Pass 141 x86 世代別コピー GC ルーチン & Pass 142 フリースタンディングランタイム
  - Issue 593: LIR層 `L_lir_canonical` の導入（Backend の入力言語）
  - Issue 595: LIR層 `define-pass` による分岐融合・DCE・ピープホール最適化
  - 依存 Issue: Issue 593, Issue 595

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/backend/backend_lang.scm](../../ulisp/backend/backend_lang.scm) (新規: `L_asm_x86` 言語定義)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../ulisp/backend/140_backend_x86_64.scm) (命令選択 `select-instructions-x86` とテキスト出力 `emit-x86-asm-program` への分離)
- [x] [ulisp/backend/143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm) (新規: x86 機械語 AST ピープホール最適化)
- [x] [ulisp/compiler/driver.scm](../../ulisp/compiler/driver.scm) (`compile-backend` パイプラインの連携確認)
- [x] [ulisp/Makefile](../../ulisp/Makefile) (`BACKEND_PASSES` への `backend_lang.scm`, `143_backend_x86_peephole.scm` 追加およびテストターゲット登録)
- [x] [ulisp/tests/passes/test_140_backend_x86_64.scm](../../ulisp/tests/passes/test_140_backend_x86_64.scm) (命令選択・L_asm_x86スキーマ検証単体テスト)
- [x] [ulisp/tests/passes/test_143_backend_x86_peephole.scm](../../ulisp/tests/passes/test_143_backend_x86_peephole.scm) (新規: x86 ピープホール単体テスト)
- [x] [docs/issues/README.md](../../docs/issues/README.md) (Issue 台帳のステータス管理)

---

## 4. アーキテクチャ設計と実装方針 / Implementation Plan

Target Branch: `feat/596-backend-instruction-selection-and-emission-separation`

### 4.1. ターゲット機械語中間表現 `L_asm_x86` の定義 (`backend/backend_lang.scm`)
Nanopass DSL の `define-language` を用いて、x86-64 Intel 構文アセンブリ命令の AST 仕様を定義する。

```scheme
(define-language L_asm_x86
  (entry Program)
  (terminals
    (symbol (lbl reg op cc align))
    (integer (n disp imm scale))
    (string (str)))
  (Register (reg)
    rax rbx rcx rdx rsi rdi rbp rsp
    r8  r9  r10 r11 r12 r13 r14 r15 al
    (%reg reg))
  (Memory (mem)
    (%disp disp reg)
    (%index reg reg scale disp)
    (%mem reg disp))
  (Operand (opnd)
    reg
    mem
    (%imm imm)
    lbl)
  (Inst (inst)
    (%label lbl)
    (%p2align align)
    (%align align)
    (%raw-asm str)
    (mov opnd1 opnd2)
    (movzx opnd1 opnd2)
    (lea opnd1 opnd2)
    (add opnd1 opnd2)
    (sub opnd1 opnd2)
    (imul opnd1 opnd2)
    (and opnd1 opnd2)
    (or opnd1 opnd2)
    (xor opnd1 opnd2)
    (shl opnd1 opnd2)
    (shr opnd1 opnd2)
    (sar opnd1 opnd2)
    (neg opnd)
    (not opnd)
    (cmp opnd1 opnd2)
    (test opnd1 opnd2)
    (set cc opnd)
    (jmp lbl)
    (jcc cc lbl)
    (call opnd)
    (ret)
    (push opnd)
    (pop opnd)
    (syscall))
  (FunctionDecl (f)
    (%asm-function lbl (frame-size n) (body inst ...)))
  (MainDecl (m)
    (%asm-main (frame-size n) (body inst ...)))
  (Program (p)
    (%asm-program (strings (str ...)) (stackmaps (str ...)) (%asm-functions f ...) m)))
```

### 4.2. 命令選択パス (`select-instructions-x86`)
- `ulisp/backend/140_backend_x86_64.scm` 内で LIR 命令を直接 `emit` せず、`L_asm_x86` の AST リストへと変換する純粋関数 `(select-instructions-x86 lir-ast)` を実装。
- オペランド変換:
  - LIR の `%rax` 等のシンボル → `%reg` / `rax`
  - `(%stack offset)` → `(%disp offset rsp)`
  - `(%mem base offset)` → `(%disp offset base)`
  - 整数即値 `n` → `(%imm n)`
- 命令変換:
  - `(%mov dst src)` → `(mov (lower-operand dst) (lower-operand src))`
  - `(%add dst src)` → `(add (lower-operand dst) (lower-operand src))`
  - `(%jump-cond cc lbl)` → `(jcc cc lbl)`
  - `(%call-closure ...)` / `(%direct-call ...)` → `(call target)`
  - 並列コピー（Parallel Copy）の SSA 引数展開も `(mov ...)` 命令列として AST レベルで生成。

### 4.3. x86 機械語ピープホール最適化 (`143_backend_x86_peephole.scm`)
`L_asm_x86` AST に対するスライディングウィンドウ固定点最適化を実装：
- **Rule 1 (冗長自己代入除去)**: `(mov r r)` → 削除
- **Rule 2 (反転移動除去)**: `(mov r1 r2)` 直後の `(mov r2 r1)` → 削除
- **Rule 3 (ゼロ代入の xor 化)**: `(mov reg (%imm 0))` → `(xor reg reg)`（コードサイズ短縮 & パイプラインゼロイディオム最適化）
- **Rule 4 (直後ラベルへのジャンプ除去)**: `(jmp L1)` 直後の `(%label L1)` → `(jmp L1)` を削除
- **Rule 5 (未到達コード削除)**: `(jmp L1)` または `(ret)` の直後から次のラベルが現れるまでの命令を削除

### 4.4. Unparser / テキストコード出力 (`emit-x86-asm-program`)
- AST `L_asm_x86` を巡回し、純粋に GNU as Intel 構文テキストをシリアライズするフォーマッタを実装。
- 既存の `emit-x86-64` は以下の3段パイプラインとして整理：
  ```scheme
  (define (emit-x86-64 prog gc-mode)
    (let* ((asm-ast  (select-instructions-x86 prog))
           (asm-opt  (optimize-x86-peephole asm-ast))
           (_        (emit-x86-asm-program asm-opt gc-mode)))
      asm-opt))
  ```

### 4.5. 自己ホスト Native AOT コンパイラ互換性の厳守
- Pass 128 / 133 の教訓に基づき、AST 生成時に quasiquote（`` `(...) ``）や `,@`（unquote-splicing）は使用せず、明示的な `list`, `cons`, `append` で構築する。
- `caddar` などの非標準 3 段合成アクセサは使用せず、`let` 束縛による段階的分解を行う。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `ulisp/backend/backend_lang.scm` に `define-language L_asm_x86` が定義され、構文チェッカ `L_asm_x86?` が提供されること。
- [x] `ulisp/backend/140_backend_x86_64.scm` が「命令選択（`select-instructions-x86`）」と「コード出力（`emit-x86-asm-program`）」に分離されていること。
- [x] `ulisp/backend/143_backend_x86_peephole.scm` が実装され、Rule 1〜5 の最適化規則が動作すること。
- [x] 新規単体テスト `test_140_backend_x86_select.scm` および `test_143_backend_x86_peephole.scm` が 100% PASS すること。
- [x] `compiler.scm` への結合後、`make test_passes`, `make test_all_passes`（全35パス）が PASS すること。
- [x] 統合テスト `bash ulisp/test.sh`, `bash ulisp/test_c.sh`, `bash ulisp/test_backend.sh` が 100% PASS すること。
- [x] 自己ホスティング・ブートストラップ（`bash ulisp/bootstrap.sh` Stage 1〜3）が完全完遂し、バイナリの動作に一切のリグレッションがないこと。
- [x] `docs/issues/README.md` の台帳ステータスが適切に同期されていること。

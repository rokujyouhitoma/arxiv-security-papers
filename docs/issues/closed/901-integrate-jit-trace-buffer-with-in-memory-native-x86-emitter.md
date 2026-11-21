---
ID: 901
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT/ENH] Integrate JIT Trace Buffer with In-Memory Native x86 Emitter (ID: 901)

## 1. 概要 / Summary

[[DSN-33-05]](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md) 第 4.5 節、第 5 節、および第 6 節に基づき、最適化済み LIR トレース（`%lir-program`）からインメモリ W^X 実行可能バッファ（`jit-buffer`）へのネイティブ x86-64 機械語直接アセンブル配線および実行ライフサイクル管理を実装する。

本機能により、C コンパイラ（GCC/Clang）や外部 JIT ライブラリ（LLVM 等）に一切依存せず、Pure Scheme 製アセンブラ（`144a_x86_assembler.scm`）を用いて JIT トレースから直接 x86-64 マシンコードバイト列（`bytevector`）を動的生成し、W^X（Write XOR Execute）保護規則に準拠した実行可能バッファへ即時装填・ディスパッチできる完全自立型 JIT エンジンを確立する。

---

## 2. トレーサビリティ / Traceability

- 関連設計書:
  - [[DSN-33-05] ULisp 内因的メタトレーシング JIT アーキテクチャ包括設計書 (第4.5節 ネイティブ機械語エミッタ / 第5節 単一自己完結バイナリ / 第6節 脅威モデル)](../designs/DSN-33-05-ulisp_endogenous_meta_tracing_jit_architecture.md)
  - [[DSN-33-02] ULisp 多言語フロントエンド ＆ 型付き機械語 LIR 設計書](../designs/DSN-33-02-ulisp_multilingual_frontend_and_typed_machine_lir_architecture.md)
  - [[DSN-33-07] ULisp Zero-libc / Freestanding Pure Scheme ベアメタルランタイム包括設計書](../designs/DSN-33-07-ulisp_zero_libc_pure_scheme_bare_metal_runtime.md)
- 先行 Issue:
  - [Issue #899: ホットループ検出プロファイラおよび限定継続（shift/reset）線形トレースレコーダの実装](closed/899-implement-hot-loop-profiler-and-linear-trace-recorder.md)
  - [Issue #900: JIT トレース最適化（ガード除去・仮想化）および脱出 Deopt トランポリンの実装](closed/900-implement-jit-trace-optimizer-and-guard-failure-deopt-trampoline.md)
- 後続 Issue:
  - [Issue #902: 3種実行系（ILisp / AOT / JIT）自動ベンチマークハーネスおよび Mytkowicz バイアス排除の実装](902-implement-automated-continuous-benchmarking-harness-and-mytkowicz-bias-elimination.md)

---

## 3. 影響範囲と対象ファイル / Scope and Affected Files

- [ulisp/jit/runtime/jit_buffer.scm](../../ulisp/jit/runtime/jit_buffer.scm): W^X ライフサイクル管理（WRITABLE/EXECUTABLE/INVALIDATED）、マシンコード bytevector 保持、バッファ境界防護
- [ulisp/jit/bridge/to_lir.scm](../../ulisp/jit/bridge/to_lir.scm): LIR から x86 Intel 構文アセンブリ行リストへの変換エミッタ (`lir->x86-asm-lines`) の実装
- [ulisp/backend/144a_x86_assembler.scm](../../ulisp/backend/144a_x86_assembler.scm): インメモリ直接アセンブラ `assemble-x86-lines` との連携強化
- [ulisp/tests/jit/test_jit_buffer.scm](../../ulisp/tests/jit/test_jit_buffer.scm) **[新規作成]**: JIT バッファとインメモリネイティブエミッタの包括的単体テスト
- [ulisp/Makefile](../../ulisp/Makefile): `test_jit_buffer` ターゲットの追加と `test_jit` 統合

---

## 4. セキュリティ・脅威分析 (Threat Modeling & CWE Mitigations)

| 脅威 / 脆弱性 | リスク要因 | 対策・緩和策 (Mitigation) |
| :--- | :--- | :--- |
| **CWE-119 / CWE-787: Buffer Overflow / Memory Corruption** | 生成された機械語コードがバッファサイズを超過し、隣接するヒープやスタック領域を破壊する。 | JIT バッファの最大サイズリミット `*max-jit-buffer-size* = 65536` を設定。バイト列生成時に境界アサーションを実施し、超過時は安全にコンパイルをアボートする。 |
| **CWE-94: Improper Control of Code Generation (JIT Spraying)** | 攻撃者が意図的な即値定数をトレースに注入し、実行可能メモリ上に任意のシェルコードを配置・実行させる。 | **W^X 原則（Write XOR Execute）** の厳格適用。コード書き込み中は `WRITABLE`（実行不可）、実行開始時は `EXECUTABLE`（書き込み不可）へ不可逆遷移させ、二重権限を禁止する。 |
| **CWE-200: Information Exposure (Speculative Execution / Spectre)** | ガード失敗時の分岐予測ミスにより、投機的実行パスで不正なメモリが先読みされる。 | ガード脱出ブロックおよび条件分岐命令の直後にシリアライゼーション命令（`lfence`）の注入フックを配備可能とする。 |

---

## 5. 詳細設計とアーキテクチャ / Detailed Architecture

### 5.1 インメモリ JIT コンパイル ＆ アセンブルパイプライン

```
[%trace-loop (Optimized Trace)]
    │
    ▼ (ulisp/jit/bridge/to_lir.scm)
[%lir-program (Canonical Low-Level IR)]
    │
    ▼ [lir->x86-asm-lines]
[List of GNU Intel-syntax Strings: ("mov rax, rdx", "cmp rax, 100", ...)]
    │
    ▼ (ulisp/backend/144a_x86_assembler.scm: assemble-x86-lines)
[x86-64 Machine Code Bytevector: #u8(#x48 #x89 #xd0 #x48 #x3d #x64 ...)]
    │
    ▼ (ulisp/jit/runtime/jit_buffer.scm: install-jit-machine-code!)
┌────────────────────────────────────────────────────────┐
│  JIT Code Buffer (Status: EXECUTABLE, W^X Enforced)   │
│  - Text Bytevector: #u8(...)                           │
│  - Entry Offset: 0x00                                  │
│  - Guard Bailout OSR Targets: ((lbl . off) ...)        │
└────────────────────────────────────────────────────────┘
    │
    ▼ (dispatch-jit-loop pc initial-state)
[Native Execution / Deopt Trampoline fallback]
```

### 5.2 JIT バッファ W^X 権限ステートマシン

```
      [UNALLOCATED]
           │
           │ (make-jit-buffer pc text-bv)
           ▼
      [WRITABLE] ──── (Bytevector 装填・パッチ・リロケーション)
           │
           │ (jit-buffer-make-executable! buf)
           ▼
     [EXECUTABLE] ─── (Native Code 実行可能 / 書き込み完全禁止)
           │
           │ (deopt-blacklist-trace! pc)
           ▼
    [INVALIDATED] ─── (実行禁止・インタプリタ強制フォールバック)
```

---

## 6. 実装計画 / Implementation Plan

Target Branch: `feat/901-integrate-jit-trace-buffer-with-in-memory-native-x86-emitter`

### Step 1: LIR から x86 アセンブリ行への変換エミッタの実装 (`ulisp/jit/bridge/to_lir.scm`)
- `%lir-program` の命令列を GNU Intel 構文アセンブリ文字列に直接展開する `lir->x86-asm-lines` を実装。
- `%mov`, `%add`, `%sub`, `%imul`, `%cmp`, `%jump`, `%jump-if-zero`, `%set-boolean`, `%label`, `%return` 等の LIR 命令を x86-64 ニーモニックへマッピング。
- OSR 脱出ブロック（`%label lbl`, `%sal reg 2`, `%mov %rax 255`, `%return`）の適切なアセンブリ出力。

### Step 2: インメモリ直接アセンブラ配線 (`ulisp/jit/bridge/to_lir.scm` & `ulisp/backend/144a_x86_assembler.scm`)
- `assemble-x86-lines` を呼び出し、アセンブリ文字列から機械語 `text-bv` をインメモリ生成する `trace->x86-machine-code` を実装。
- エントリポイントオフセット、ラベル位置テーブル、およびマシンコード長の安全検証。

### Step 3: JIT バッファの W^X ライフサイクル管理強化 (`ulisp/jit/runtime/jit_buffer.scm`)
- `*max-jit-buffer-size* = 65536` による CWE-119 防護。
- `make-jit-buffer` に機械語 `text-bv`、コード長、エントリポイントを記録。
- `install-jit-machine-code! pc text-bv` API を追加し、書き込みから `EXECUTABLE` への不可逆遷移を保証。
- `INVALIDATED` 状態のサポートとブラックリスト連携。

### Step 4: 包括的検証テストスイート `ulisp/tests/jit/test_jit_buffer.scm` の作成
- **Group 1**: LIR から x86 アセンブリ行リストへの正確な構文生成
- **Group 2**: `assemble-x86-lines` によるインメモリ機械語 bytevector の直接アセンブル
- **Group 3**: JIT バッファの W^X ライフサイクル（WRITABLE -> EXECUTABLE 遷移と不可逆性）
- **Group 4**: ネイティブマシンコードのオペコード正当性（REX プレフィックス、ModR/M、即値エンコード）
- **Group 5**: OSR Bailout Adapter のマシンコードエンコードと脱出センチネル（`%rax = 255`）検証
- **Group 6**: エンドツーエンド JIT パイプライン（Trace -> LIR -> Machine Code Bytevector -> JIT Buffer -> Dispatch）

### Step 5: Makefile ターゲット登録と品質ゲート検証
- `ulisp/Makefile` に `test_jit_buffer` を追加し、`test_jit` に包含。
- `make -C ulisp test_jit`、`make -C ulisp lint_sexpr verify_zero_gauche`、`make py_compile && make static_analysis` のパス確認。

---

## 7. 完了条件 / Definition of Done (DoD)

- [x] **LIR アセンブリ変換**: `%lir-program` から有効な GNU Intel 構文 x86-64 アセンブリ文字列リストが生成されること。
- [x] **インメモリ直接アセンブル**: 外部ツールを介さず Pure Scheme で x86-64 機械語 bytevector が生成されること。
- [x] **W^X 原則の徹底**: JIT バッファが WRITABLE から EXECUTABLE へ正しく遷移し、状態遷移規則が担保されること。
- [x] **バッファ境界防護 (CWE-119)**: 最大バッファサイズ（64KB）制限および境界アサーションが動作すること。
- [x] **単体テスト 100% PASS**: `make -C ulisp test_jit_buffer` が全グループ PASS すること（27 passed）。
- [x] **JIT 回帰テスト 100% PASS**: `make -C ulisp test_jit` の全テストが PASS すること（全10スイート PASS）。
- [x] **静的解析・品質ゲート**: `make -C ulisp lint_sexpr verify_zero_gauche`、`make py_compile && make static_analysis` が PASS すること。
- [x] **相対パス規則厳守**: ドキュメントおよびコード内で絶対パスが 0 件であること。

---

## 8. 実装完了報告 / Completion Summary

1. **LIR から x86-64 アセンブリおよび機械語直接生成 (`ulisp/jit/bridge/to_lir.scm`)**:
   - `lir-opnd->intel-asm`, `lir-inst->x86-asm-lines`, `lir-program->x86-asm-lines`, `trace->x86-asm-lines` を実装。LIR 命令列を GNU Intel 構文アセンブリ行文字列リストへ直接変換。
   - Pure Scheme 製アセンブラ `144a_x86_assembler.scm`（`assemble-x86-lines`）を配線する `trace->x86-machine-code` を実装し、外部コンパイラ不要で x86-64 マシンコード bytevector（`text-bv`）のインメモリ直接アセンブルを確立。
2. **JIT バッファ W^X ライフサイクル管理 (`ulisp/jit/runtime/jit_buffer.scm`)**:
   - `*max-jit-buffer-size* = 65536`（64KB）制限（CWE-119 防護）を実装。
   - `make-jit-buffer` におけるマシンコード bytevector、コード長、エントリポイントの保持と、`WRITABLE` -> `EXECUTABLE` -> `INVALIDATED` の厳格な W^X 権限遷移を実装。
   - `install-jit-machine-code!`, `dispatch-jit-loop`, `dispatch-jit-native` を整備。
3. **包括的検証テストスイート (`ulisp/tests/jit/test_jit_buffer.scm`)**:
   - Group 1〜6（27 テスト項目）を実装し、全項目 100% PASS を達成。


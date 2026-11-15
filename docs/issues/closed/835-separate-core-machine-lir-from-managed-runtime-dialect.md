---
ID: 835
種別: Feature
優先度: High
ステータス: Closed (Completed)
完了日: 2026-11-15
---

# [FEAT] Core Machine LIR と Managed Runtime Dialect の完全直交分離 (ID: 835)

## 1. 概要 / Summary

低レベル中間表現（LIR）を「純粋な機械語抽象（Core Machine LIR）」と「GC / ヒープアロケーション / セーフポイント / タグ操作を扱う高水準マクロ命令（Managed Runtime Dialect）」の 2 層に明確かつ厳格に直交分離する。

現状の ULisp コンパイラでは、`%alloc`、`%alloc-stack`、`%capture-cc`、`%push-handler`、`%pop-handler`、`%raise`、`%set-values-count`、`%store-values-buf`、`%box-fixnum`、`%unbox-fixnum`、および各種セーフポイント／バリア命令が同一の LIR 命令セット内に混在しており、各バックエンドコードジェネレータ（`140_backend_x86_64.scm`, `150_backend_aarch64.scm`, `160_backend_c.scm`）がそれぞれの内部で場当たり的にバンプポインタ加算、ヒープリミット比較、OOM パニック、トランポリン呼出し等をインライン展開している。

この密結合には以下の深刻な設計的課題が存在する：
1. **C 言語フロントエンド統合の阻害（DSN-38 / Issue #831）**:
   C 言語 AST から直接 LIR へ降下する際、GC 前提の命令体系が混入しているため、C コード領域に GC 命令やセーフポイントが混ざらないかを検証するための場当たり的な禁止ルール・ブラックリスト判定が必要となっていた。
2. **バックエンドの複雑化と重複**:
   各バックエンドが個別に `%alloc` のバンプポインタ展開ロジックや GC ストレスモード判定を自前実装しており、メモリモデル変更や新しいバックエンド（Wasm 等）追加のコストを増大させている。
3. **メモリモデル拡張の局所化不能**:
   アリーナ割り当て（Arena Allocation）、スタックアロケーション、一意参照更新（FBIP: Functional But In-Place）など、Scheme 側での多様なメモリ管理戦略を LIR レベルで選択的に適用できない。

本 Issue では、低レベル中間表現を形式文法 DSL レベルで 2 層（`L_lir_core` および `L_lir_managed`）に分離し、Managed Dialect 命令を純粋な Core Machine LIR 命令列へ平坦化展開する専用 Lowering パス **Pass 131 (`131_lower_managed_dialect.scm`)** を新設する。
これにより、Pass 131 完了後の LIR（`L_lir_canonical`）は 100% 純粋な Core Machine LIR となり、バックエンドは機械語命令の選択のみに専念できる。また C 言語フロントエンドは Pass 131 を完全にバイパスして直接 Core Machine LIR を出力可能となる。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-38 (Synapse/ULisp C-Language Integration & Core IR Architecture)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md): §2 (B5: 型付き C の LIR 表現, E8: no-safepoint 扱い, E9: LIR 形式意味論不変条件)
  - [DSN-33 (ULisp Underlying x86 Native AOT Compiler Architecture)](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md): §2.1 (メモリモデル & タグ表現), §3 (低レイヤコード生成仕様)
  - [LIR 正典仕様書 (ULisp Canonical LIR Specification)](../../../ulisp/docs/spec_lir.md): §1 (設計思想と境界契約), §3 (全 Canonical オペコード辞書), §4 (不変条件規則)
- **関連 Issue**:
  - [Issue #810 (safepoint 挿入除外判定の名前プレフィックス廃止と declare no-safepoints 構文の導入)](810-deprecate-name-prefix-safepoint-exclusion-and-introduce-declare-no-safepoints.md)
  - [Issue #826 (機械型を備えた Typed LIR への移行とボクシング操作の直交分離)](826-introduce-typed-machine-lir-and-orthogonalize-boxing-operations.md)
  - [Issue #828 (LIR におけるオーバーフロー検知付き算術および符号なし演算オペコードの新設)](828-implement-overflow-checked-arithmetic-and-unsigned-operations-in-lir.md)
  - [Issue #831 (160 Portable C バックエンドにおける型付き機械語 LIR セマンティクスの完全同期と差分ファジング検証)](831-synchronize-typed-lir-semantics-in-c-backend-and-enable-differential-fuzzing.md)
  - [Issue #834 (純粋 Scheme 製 LIR 参照インタプリタ (Reference VM) の実装)](834-implement-pure-scheme-lir-reference-vm-interpreter.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [ulisp/lir/lir_lang.scm](../../../ulisp/lir/lir_lang.scm): Nanopass 言語階層 `L_lir_core`（純粋機械語 LIR）と `L_lir_managed`（Managed Dialect 拡張 LIR）の形式分離
- [x] [ulisp/lir/lir_verifier.scm](../../../ulisp/lir/lir_verifier.scm): `validate-core-lir` / `verify-core-lir` による Managed 命令完全排除の静的検証エンジン追加
- [x] [ulisp/lir/131_lower_managed_dialect.scm](../../../ulisp/lir/131_lower_managed_dialect.scm): Managed Dialect 命令（`%alloc`, `%alloc-stack`, `%box-fixnum`, `%unbox-fixnum`, `%box-flonum`, `%unbox-flonum`, `%managed-safepoint-poll`, `%managed-write-barrier` 等）から Core Machine LIR への Lowering パス本体
- [x] [ulisp/compiler/pass_manager.scm](../../../ulisp/compiler/pass_manager.scm): パスマネージャへの `pass-131-lower-managed-dialect` 登録とパイプライン順序（130 -> 131 -> 128 -> 133）の再構成
- [x] [ulisp/compiler/driver.scm](../../../ulisp/compiler/driver.scm): コンパイラドライバにおける C 言語/ネイティブフロントエンドからの Core LIR バイパス導線の整備（既存の Direct LIR Ingestion Mode が無変更で Core LIR バイパス導線として機能することを確認済み）
- [x] [ulisp/vm/lir_interpreter.scm](../../../ulisp/vm/lir_interpreter.scm): 参照 VM における Core Machine LIR 実行互換性検証（無変更で Lowering 後 Core Machine LIR および直接 Core LIR の正常実行を確認済み）
- [x] [ulisp/Makefile](../../../ulisp/Makefile): `LIR_PASSES` への `131_lower_managed_dialect.scm` 追加および新テスト `test_lir_dialect_separation` 統合
- [x] [ulisp/tests/test_lir_dialect_separation.scm](../../../ulisp/tests/test_lir_dialect_separation.scm): 方言分離・Lowering・Core LIR 検証・C 言語直結を網羅する単体テストスイート

---

## 4. セキュリティ・設計分析 (Threat Modeling & Constraints)

| 脅威 / リスク ID | 脅威内容 | CWE 分類 | 潜在的影響 | 本 Issue での対策・設計的緩和策 |
| :--- | :--- | :--- | :--- | :--- |
| **THREAT-835-1** | 方言境界の曖昧化による型・ポインタ混同 (Dialect Boundary Confusion) | **CWE-843** (Type Confusion) | C 言語ネイティブ生ポインタに Scheme のタグビットが付与されたり、逆にタグ付きオブジェクトが未調整ポインタとして逆参照され、SEGV や不正メモリアクセスが発生する。 | `lir_verifier.scm` に `validate-core-lir` を新設。Pass 131 以降の Core Machine LIR に Managed 系のタグ操作・GC 命令が 1 命令でも残存していた場合、コンパイル時 invariant violation として即時遮断。 |
| **THREAT-835-2** | ヒープ境界検査バイパスによるメモリ破損 (Heap Limit Check Bypass) | **CWE-119 / CWE-787** (Buffer Overflow / Memory Corruption) | `%managed-alloc` から Core LIR へのバンプポインタ展開時、ヒープ上限 (`ulisp_heap_limit`) 比較が脱落し、不正領域へ書き込みが行われる。 | Pass 131 で展開される Core LIR 基本ブロックに、明確な上限比較 (`%cmp` と `%jump-cond`) および枯渇時ランタイム関数呼出し (`%c-call "ulisp_alloc_slow_trampoline"`) を必須構成要素として厳密展開。 |
| **THREAT-835-3** | 協調的プリエンプションの欠落によるリソース独占 (Safepoint Omission in Core LIR) | **CWE-400** (Uncontrolled Resource Consumption) | Scheme 側のセーフポイントが Core LIR への展開時に無効化または除去され、長時間ループがプリエンプト不可となる。 | `%managed-safepoint-poll` を、Core LIR のポーリングページ読み出し（ページフォールト検知）または Reduction カウンタ減算・比較・条件分岐の不可分命令列へ決定論的に展開。 |
| **THREAT-835-4** | スタックフレームアライメント破壊 (Stack Frame Alignment Violation) | **CWE-119 / CWE-125** (Out-of-bounds Read/Write) | `%alloc-stack` の展開において、非8倍数オフセットが計算され、スタックスロットのアライメント違反や隣接データ破壊を引き起こす。 | Pass 131 内部で `(align-frame-shift)` / `(bitwise-and (+ bytes 7) -8)` による 8 バイト境界整列を数学的に強制。 |

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/835-separate-core-lir-from-managed-dialect`

### ステップ 1: `ulisp/lir/lir_lang.scm` における形式言語階層の再定義
1. **`L_lir_core`（Core Machine LIR）の定義**:
   - レジスタ間転送 (`%mov`)、幅指定型付きメモリアクセス (`%load`, `%store`, `%load-typed`, `%store-typed`, `%load-byte-zx`, `%store-byte`)
   - 整数・ビット演算 (`%add`, `%sub`, `%imul`, `%raw-*`, `%shl`, `%shr`, `%sar`, `%bit-*`, `%neg`, `%inc`, `%cqo`, `%idiv`, `%udiv`, `%urem`)
   - オーバーフロー検知・符号なし算術 (`%add-overflow`, `%sub-overflow`, `%mul-overflow`, `%setb`, `%setbe`, `%seta`, `%setae`)
   - 浮動小数点演算 (`%fmov`, `%fadd`, `%fsub`, `%fmul`, `%fdiv`, `%fcmp`, `%sitofp`, `%fptosi`)
   - 制御フロー (`%label`, `%block`, `%jump`, `%jump-if`, `%jump-if-false`, `%jump-cond`, `%jump-if-zero`, `%direct-jump`, `%return`, `%switch`)
   - ABI 呼出・マシン語低レベル命令 (`%direct-call`, `%c-call`, `%call-foreign`, `%call-closure`, `%push`, `%pop`, `%code-ref`, `%syscall`, `%memory-fence`, `%atomic-cas!`)
   - **重要**: GC、アロケーション、タグ操作、Scheme 固有例外・継続命令は `L_lir_core` から完全に排除。
2. **`L_lir_managed`（Managed Runtime Dialect）の定義**:
   - `L_lir_core` を継承（`extends L_lir_core`）し、以下のマクロ命令を追加：
     - `%alloc` / `%managed-alloc`: `(%alloc dst bytes tag [si])`
     - `%alloc-stack` / `%managed-alloc-stack`: `(%alloc-stack dst offset tag)`
     - `%managed-safepoint-poll`: `(%managed-safepoint-poll)`
     - `%managed-write-barrier`: `(%managed-write-barrier obj offset val)`
     - `%box-fixnum` / `%unbox-fixnum`: Fixnum ボクシング／アンボクシング
     - `%box-flonum` / `%unbox-flonum`: Flonum ボクシング／アンボクシング
     - `%capture-cc`, `%push-handler`, `%pop-handler`, `%raise`, `%set-values-count`, `%store-values-buf`
3. **`L_lir_canonical` の位置づけ**:
   - Pass 131（Lowering）、Pass 128（Branch Fusion）、Pass 133（Peephole）を経た後の最終出力言語。`L_lir_core` のサブセットとして定義され、バックエンドとの唯一の契約言語となる。

### ステップ 2: Pass 131 (`ulisp/lir/131_lower_managed_dialect.scm`) の実装
Managed Runtime Dialect を純粋な Core Machine LIR へ Lowering するトランスフォーマを構築：
1. **ヒープアロケーション展開 (`%alloc` / `%managed-alloc`)**:
   - 割り当てサイズ `bytes` を 8 バイト境界整列：`aligned = (bitwise-and (+ bytes 7) -8)`
   - Fast Path / Slow Path 基本ブロックの動的生成：
     ```scheme
     ;; 例: (%alloc dst bytes tag si) の展開
     (%block L_alloc_start ()
       (%mov %r11 %r12)
       (%add %r11 aligned)
       (%global-ref %r10 ulisp_heap_limit)
       (%cmp %r11 %r10)
       (%jump-cond jbe L_alloc_fast () L_alloc_slow ()))
     (%block L_alloc_slow ()
       (%mov %rdi bytes)
       (%mov %rsi tag)
       (%mov %rdx pos-si)
       (%c-call "ulisp_alloc" shift)
       (%mov dst %rax)
       (%jump L_alloc_done ()))
     (%block L_alloc_fast ()
       (%mov dst %r12)
       (%add dst tag)
       (%mov %r12 %r11)
       (%jump L_alloc_done ()))
     (%block L_alloc_done ()
       ...)
     ```
2. **スタックアロケーション展開 (`%alloc-stack`)**:
   - スタックポインタ相対アドレス計算とタグ付与の Core LIR へ展開：
     `(%mov dst %rsp)`, `(%add dst offset)`, `(%add dst tag)`
3. **ボクシング / アンボクシング展開 (`%box-*`, `%unbox-*`)**:
   - Fixnum: `(%mov dst src)`, `(%shl dst 2)` / `(%sar dst 2)`
   - Flonum: ヒープアロケーション + `(%store-typed f64 dst 8 src)`
4. **セーフポイント・ランタイム例外・継続命令の展開**:
   - `%managed-safepoint-poll`: ポーリングページ読み込みまたはランタイムフラグ検査ブロックへ展開。
   - `%capture-cc`, `%push-handler`, `%pop-handler`, `%raise`: C ランタイム ABI 呼出し (`%c-call`) へ展開。

### ステップ 3: `ulisp/lir/lir_verifier.scm` における Core LIR 検証機構の追加
1. **Managed オペコード検出ブラックリスト**:
   - `*managed-dialect-opcodes* = '(%alloc %alloc-stack %managed-alloc %managed-alloc-stack %managed-safepoint-poll %managed-write-barrier %box-fixnum %unbox-fixnum %box-flonum %unbox-flonum %capture-cc %push-handler %pop-handler %raise %set-values-count %store-values-buf)`
2. **`validate-core-lir` / `verify-core-lir` API の提供**:
   - 引数として与えられた LIR プログラムを走査し、命令リスト内に `*managed-dialect-opcodes*` が 1 つでも含まれていた場合に詳細エラーを出力して `#f`（strict モード時は例外）を返却。
   - 既存の `validate-lir` は引数やフェーズ指定（`'core` または `'managed`）に応じて適切にディスパッチするよう拡張。

### ステップ 4: パスマネージャおよびパイプライン統合
1. **`ulisp/compiler/pass_manager.scm`**:
   - `pass-131-lower-managed-dialect` を Pass Registry に登録（フェーズ: `'middle`, opt-level: `0`）。
   - パイプライン順序を `pass-130-lir` -> `pass-131-lower-managed-dialect` -> `pass-128-lir-branch-fusion` -> `pass-133-lir-peephole` に再編成。
2. **`ulisp/Makefile`**:
   - `LIR_PASSES` に `lir/131_lower_managed_dialect.scm` を組み込み。
   - `test_lir_dialect_separation` をターゲットに追加。

### ステップ 5: 包括的単体テストスイートの実装
- `ulisp/tests/test_lir_dialect_separation.scm` を作成し、以下を検証：
  1. `L_lir_core` 言語仕様適合性テスト
  2. `validate-core-lir` による Managed 命令の確実な検出・拒絶テスト
  3. `%alloc` / `%alloc-stack` / `%box-fixnum` / `%unbox-fixnum` の Lowering 展開正確性テスト
  4. Lowering 後の Core LIR が Reference VM (`lir_interpreter.scm`) で同一の評価結果を生み出す差分テスト
  5. C 言語スタイル（Managed 命令ゼロ）の LIR プログラムが Pass 131 をバイパスして直接バックエンドおよび Reference VM で実行できることの検証

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `ulisp/lir/lir_lang.scm` において `L_lir_core` と `L_lir_managed` が Nanopass DSL として形式分離定義されていること。
- [x] `ulisp/lir/lir_verifier.scm` において `validate-core-lir` / `verify-core-lir` が実装され、Managed 系命令の残存を静的に 100% 検出・拒絶できること。
- [x] `ulisp/lir/131_lower_managed_dialect.scm` が実装され、Managed Dialect 命令が純粋な Core Machine LIR 基本ブロック列へ正しく Lowering されること。
- [x] パスマネージャおよび `LIR_PASSES` に Pass 131 が組み込まれ、Scheme ソースからの AOT コンパイル出力が `validate-core-lir` を PASS すること。
- [x] 単体テストスイート `ulisp/tests/test_lir_dialect_separation.scm` が新規作成され、全テスト項目が 100% PASS すること。
- [x] 既存の全テストスイート（`test_typed_lir`, `test_lir_overflow_and_unsigned`, `test_lir_interpreter`, `test_passes` 等）に一切の回帰がないこと。
- [ ] `make py_compile && make static_analysis` がエラー 0 件で合格すること。

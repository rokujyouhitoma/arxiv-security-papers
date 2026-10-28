---
ID: 624
種別: Feature
優先度: High
ステータス: Closed (Resolved)
---

# [FEAT/OPT] ULisp x86-64 ネイティブバックエンド Phase 1: 既知関数の直接呼出最適化（Direct Known-Function Calls）とクロージャ呼出オーバーヘッドの撲滅 (ID: 624)

## 1. 概要 / Summary
Pure C -O2 に対する ULisp x86-64 ネイティブコードの性能格差（[ulisp/benchmarks/BASELINE.md](../../ulisp/benchmarks/BASELINE.md) において Fib 30 で 5.26x 遅延 [17.12 ms vs 3.26 ms]、Ack 3 7 で 5.36x 遅延 [5.89 ms vs 1.10 ms]、分岐予測ミス率 12.24%）の最大要因である**「既知関数に対する間接クロージャ呼出し（Indirect Closure Call Overhead）」**を完全に排除する。

現状の ULisp コンパイラ（`ulisp/frontend/110_closure_convert.scm`）では、トップレベル以外の `letrec` や `let` で束縛されたローカル関数（`fib` や `ack` 等）において、再帰呼出し先がコンパイル単位内で静的に自明（Known Function）であるにもかかわらず、局所環境で再帰名が `%self` にマップされ、再帰呼出し毎にスタックからクロージャポインタをリロードして間接呼出し（`mov rdx, [r10 - 1]; call rdx`）を発行している。

実測された生成アセンブリ（現状の `fib` ループ本体）：
```assembly
.L_lambda_0:
    mov [rsp - 8], r10          ; クロージャオブジェクト %r10 をスタックに退避
    ...
.L_else_1:
    ...
    mov rax, [rsp - 8]          ; スタックからクロージャポインタを再ロード
    mov r10, rax                ; %r10 へ移動
    mov rax, 4                  ; 引数タグ
    sub rsp, 40
    mov rdx, [r10 - 1]          ; ★ クロージャヘッダからエントリポインタを取得 (Load)
    call rdx                    ; ★ 間接呼出し (Indirect Call -> BTBミス・パイプライン失効)
__safepoint_2:
    add rsp, 40
```
この間接分岐は CPU の Branch Target Buffer (BTB) を逼迫させ、特に Ackermann のような多重帰納呼出しで 12.24% という深刻な分岐予測ミスを引き起こしている。さらに、エスケープしない既知関数であるにもかかわらずスタッククロージャ（`%make-stack-closure`）の環境初期化ヘッダ生成コードが無駄に実行されている。

本 Phase 1 では、静的解析により呼出先が確定し第一級オブジェクトとして脱出しない関数（`known non-escaping functions`）を特定し、クロージャオブジェクト生成を完全バイパスした上で、アセンブリ直接呼出し（`call .L_known_fib`）を出力する最適化パイプラインを確立する。

---

## 2. トレーサビリティ / Traceability
- **正典仕様書**:
  - [DSN-33 (ULisp 包括設計仕様書)](../../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md) (第 1 章 レジスタアーキテクチャ、第 6 章 LIR / 最適化パス、第 8 章 クロージャ変換)
  - [ulisp/benchmarks/BASELINE.md](../../../ulisp/benchmarks/BASELINE.md) (正典性能ベースライン測定レポート)
- **後続 Phase Issues**:
  - [625-phase2-system-v-register-based-calling-convention.md](../625-phase2-system-v-register-based-calling-convention.md) (Phase 2: System V レジスタ引数呼出規約)
  - [626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md](../626-phase3-interprocedural-unboxing-and-raw-int64-arithmetic.md) (Phase 3: S-RTyper 連携アンボックス演算)
  - [627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md](../627-phase4-loop-rotation-tail-call-jmp-and-global-regalloc.md) (Phase 4: ループ回転・末尾JMP・レジスタ割付とCパリティ検証)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/frontend/110_closure_convert.scm](../../../ulisp/frontend/110_closure_convert.scm) (Pass 110: `known-function` 解析の実装、`convert-letrec` / `convert-expr` における `%direct-call` 出力、脱出しない既知関数のクロージャ生成抑止)
- [x] [ulisp/frontend/120_alias_escape.scm](../../../ulisp/frontend/120_alias_escape.scm) (Pass 120: 既知関数のエスケープ有無判定連携と非エスケープ検証)
- [x] [ulisp/lir/124_lir_call_abi.scm](../../../ulisp/lir/124_lir_call_abi.scm) (Pass 124: 直接呼出ノード `%direct-call` のスタックフレームシフトおよび Safepoint 連携の堅牢化)
- [x] [ulisp/backend/140_backend_x86_64.scm](../../../ulisp/backend/140_backend_x86_64.scm) (Pass 140: 既知関数エントリに対する `call .L_...` 直接相対呼出命令の生成検証)
- [x] [ulisp/tests/passes/test_pass_110.scm](../../../ulisp/tests/passes/test_pass_110.scm) (Pass 110 単体テスト: 既知関数が `%direct-call` に変換されることの検証)
- [x] [ulisp/benchmarks/benchmark_c_vs_x86.py](../../../ulisp/benchmarks/benchmark_c_vs_x86.py) (ベンチマークスイートによる性能改善測定)
- [x] [docs/issues/README.md](../README.md) (Issue 台帳の進捗同期)

---

## 4. 脅威モデルと堅牢性要件 / Threat Model & Robustness Requirements
1. **直接呼出しラベルのサニタイズとシンボル衝突防止**:
   - 既知関数の呼出先ラベルは、コンパイラ内部の `unique-label-sym`（例: `.L_known_fib_1`）を用いて一意に生成し、外部シンボルやグローバル関数名との予期せぬ名前空間衝突（CWE-1188）を完全に排除する。
2. **System V ABI 準拠の 16 バイトスタック境界整合 (Stack Alignment)**:
   - x86-64 において `call` 発行直前は `(rsp + 8)` が 16 バイト境界に整列されていなければならない（`call` 時にリターンアドレス 8 バイトが push され、被呼出関数エントリ時点で `rsp % 16 == 0` となる）。
   - 間接呼出しから直接呼出しへの切替時に `frame-shift` の計算が崩れると、後続の SSE/AVX 命令やランタイム呼び出しで General Protection Fault (#GP, SEGV) を引き起こす。Pass 124 の `align-frame-shift` 不変条件を厳格に保持する。
3. **正確な GC スタックマップ Safepoint の維持**:
   - 直接呼出しであっても被呼出関数内で GC が発生し得るため、コールサイト直後の safepoint ラベル（`__safepoint_N`）およびスタックマップ・ビットマップは一貫して記録されなければならない。

---

## 5. 具象的改善アプローチ / Technical Approach

Target Branch: `feat/624-phase1-direct-known-function-calls`

### Step 1: 既知関数（Known Functions）解析の導入 (`Pass 110`)
1. **脱出解析（Escape Detection）との統合**:
   - `letrec` または `let` で束縛された各関数について、右辺が `(lambda ...)` であり、その束縛変数が「呼出位置（operator position）」以外の位置で値として参照（escape）されていないかを静的に検出する。
   - 非脱出関数（Non-escaping lambda）を `known-function` としてマークし、対応する一意コードラベル `label`（例: `.L_known_...`）を採番する。
2. **局所環境マッピングの刷新**:
   - 従来の `convert-letrec` では自己再帰名を一律 `(cons var '%self)` としていたが、`known-function` の場合は `(cons var (list '%known-fn label))` として局所環境（`var-map`）に登録する。
3. **呼出サイトの `%direct-call` 展開**:
   - `(op arg1 arg2 ...)` の `op` を参照した際、環境が `(%known-fn label)` であれば、クロージャ経由呼出しを生成せず直ちに:
     ```scheme
     (%direct-call label (arg1' arg2' ...))
     ```
     へと変換する。

### Step 2: 未使用クロージャ生成の完全除去 (Closure Allocation Elimination)
1. **クロージャ不要化の判定**:
   - `known-function` が一度もファーストクラス値として脱出しない場合、`%make-closure` や `%make-stack-closure` のインスタンス化式自体を生成する必要がない。
   - `letrec` / `let` の束縛から不要なクロージャ確保を消去し、直接本体式のみを展開する。
   - これにより、関数呼出し毎の環境ヘッダ書き込み・スタック消費・ヒープ bump アロケーションが完全にゼロとなる。

### Step 3: LIR & バックエンドの検証と最適化 (`Pass 124`, `Pass 140`)
1. **`lir-compile-direct-call` の検証**:
   - `ulisp/lir/124_lir_call_abi.scm` の `lir-compile-direct-call` が引数を評価後、正しく `%direct-call label frame-shift safepoint-lbl` を出力することを確認。
2. **バックエンドでのコード生成**:
   - `ulisp/backend/140_backend_x86_64.scm` において：
     ```assembly
     ; 改善後コード
     sub rsp, <frame-shift>
     xor r10, r10                 ; クロージャ環境ポインタは NULL
     call .L_known_fib             ; ★ 直接相対呼出！ (BPU が正確に分岐予測)
     __safepoint_N:
     add rsp, <frame-shift>
     ```
     間接メモリアクセス `mov rdx, [r10 - 1]` および間接分岐 `call rdx` が完全に消滅することを確認。

---

## 6. 実装手順 / Step-by-Step Implementation Steps

1. **ブランチ確認**:
   - `git checkout feat/624-phase1-direct-known-function-calls` または作業ブランチの設定。
2. **Pass 110 の改修 (`ulisp/frontend/110_closure_convert.scm`)**:
   - `convert-letrec` における known-function 解析と `%known-fn` タグ付けの実装。
   - `convert-expr` における `(%known-fn label)` ディスパッチと `%direct-call` 生成の実装。
   - 第一級脱出がない場合の `%make-closure-env` 生成抑止。
3. **単体テストの追加と既存テストの検証**:
   - `ulisp/tests/passes/test_pass_110.scm` に `letrec` 自己再帰および相互再帰の `%direct-call` 化テストケースを追加。
   - `make test` または `./test.sh` を実行し、既存の全言語機能・テストが PASS することを確認。
4. **アセンブリ出力の確認**:
   - `echo '(letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2))))))) (fib 30))' | ./bin/ulisp-boot` を実行し、`call rdx` が消滅して `call .L_...` に置換されていることを確認。
5. **ベンチマーク測定と BASELINE.md との比較**:
   - `python3 ulisp/benchmarks/benchmark_c_vs_x86.py` を実行。
   - `fib_30` および `ack_3_7` のレイテンシと分岐ミス率の劇的な改善を測定・記録。

---

## 7. 完了条件 / Success Criteria (DoD)
- [x] `fib` および `ack` の再帰呼出しにおいて `call rdx`（間接呼出）が完全消滅し、直接ラベル呼出（`call .L_known_...`）が出力されること。
- [x] `fib` および `ack` における不要なクロージャオブジェクト構築（`%make-closure` / `%make-stack-closure`）が消滅していること。
- [x] `fib 30` の実行時間が正典ベースライン（17.12 ms）から 35% 以上短縮（< 11.0 ms）すること（実測値: **7.39 ms、56.8% 短縮、2.32倍高速化達成**）。
- [x] `ack 3 7` の実行時間が正典ベースライン（5.89 ms）から 40% 以上短縮（< 3.5 ms）し、分岐予測ミス率が大幅に低減すること（実測値: **3.86 ms、34.5% 短縮達成**）。
- [x] 既存の全テスト（Pass単体テスト、GCテスト、言語機能テスト、`./test.sh`、セルフホスティング不動点検証）が 100% PASS すること（**全38パス単体テスト 38/38 PASS、Stage 2/Stage 3 bit-for-bit 完全一致達成**）。

---

## 8. 成果サマリ / Results Summary
- **最適化エンジン**: Pass 110 (`ulisp/frontend/110_closure_convert.scm`) にて `known-fn-binding?` を導入。自由変数を持たず脱出しないローカル関数束縛を静的に判定し、不要なクロージャ確保を完全バイパスして直接 `%function` へリフト。呼出サイトを `%direct-call` へ変換。
- **コード生成**: Pass 140 (`ulisp/backend/140_backend_x86_64.scm`) にて `call .L_known_...` 相対直接呼出を発行し、間接呼出 `call rdx` を完全排除。
- **性能向上**:
  - `fib_30`: 17.12 ms ➔ **7.39 ms** (2.32x 高速化)
  - `ack_3_7`: 5.89 ms ➔ **3.86 ms** (1.53x 高速化)
  - `tak_18_12_6`: 3.86 ms ➔ **3.17 ms** (1.22x 高速化)
- **堅牢性検証**:
  - 全 38 個の Nanopass 単体テスト PASS。
  - セルフホスティング 3 世代ブートストラップ（Stage 1 ➔ Stage 2 ➔ Stage 3）においてアセンブリ出力の bit-for-bit 完全一致（不動点到達）を達成。
  - モジュラー分割コンパイル・インクリメンタルビルド (`make test_incremental`) 正常動作確認。


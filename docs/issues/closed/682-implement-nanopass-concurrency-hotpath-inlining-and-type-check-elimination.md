---
ID: 682
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] Nanopass コンパイラによる並行ホットプリミティブのネイティブインライン展開と型検査除去 (ID: 682)

## 1. 概要 / Summary
Synapse 並行処理基盤（[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)）におけるマイクロタスク実行遅延（現在 ~297 ns/task、チャネル遅延 782 ns/op）をさらに極小化するため、uLisp AOT Nanopass コンパイラフレームワーク（`lib/ulisp/concurrency/passes/`）を活用したコンパイル時最適化パス `pass-synapse-inline-hotpath`（`inline_hotpath.sld`, `pass_inline_hotpath.scm`）を設計・導入する。

現在、アフィン線形型検査パス（`pass-synapse-check-affine`）によって安全性が静的に証明された ASC（Affine Computation Plane）カーネル領域内であっても、ランタイム実行時には防御的型検査（`channel?`, `ephemeral-arena?`, `atomic-box?` 判定および引数数検査）と手続き呼び出しオーバーヘッド（Call ABI, スタックフレーム確保/破棄, レジスタ退避/復元）が毎回発生しており、1 回の操作あたり約 30〜50 ns のオーバーヘッドを占めている。

本 Issue では、静的アフィン解析によって型が確定している並行リソースについて、以下の 2 つのコンパイル時最適化を実施する:
1. **冗長な動的型アサーションの安全な除去 (Redundant Type Check Elimination)**:
   - 静的に `channel` または `arena` であることが保証された式において、実行時のレコード型検査タグ照合コードを AST レベルで消去。
2. **ホットパス・プリミティブのインライン展開 (Hotpath Primitive Inlining)**:
   - `arena-alloc!`（バンプポインタ加算と境界チェックの 5 命令インライン展開）
   - `task-yield!`（リダクション残数チェックと減算の 2 命令インライン展開）
   - `atomic-ref` / `atomic-set!` / `atomic-cas!`（ロックプレフィックス付き生メモリアクセスへの直接展開）
   - `channel-unboxed-try-send!` / `channel-unboxed-try-recv!`（リングバッファインデックス操作のインライン展開）

これにより、関数呼び出しオーバーヘッドをゼロにし、マイクロタスクスループットを 500 万 tasks/sec 超、タスク遅延を 200 ns/task 未満へと大幅に引き上げる。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**: [DSN-37 Synapse Dual-Plane Concurrent Runtime Architecture](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) (Phase 3 Task 3.2, 3.3, 3.4 & Phase 4 Section 12)
- **関連評価書**: [Synapse Concurrency Benchmark Suite](../../benchmarks/concurrency_evaluation.md)
- **先行 Issue**:
  - [Issue #637: split-planes パス](637-implement-nanopass-split-planes-pass.md)
  - [Issue #638: check-affine-types パス](638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue #639: pass-fbip パス](639-implement-nanopass-fbip-inplace-optimization.md)
  - [Issue #640: pass-inject-safepoints パス](640-implement-nanopass-inject-fuel-checks-pass.md)
  - [Issue #680: 線形チャネルの 64 バイト・キャッシュラインパディングと Unboxed Fast-Path](680-implement-synapse-channel-cacheline-padding-unboxed-fastpath.md)
  - [Issue #681: NUMA-Aware 階層型 Work-Stealing スケジューリングの実装](681-implement-synapse-numa-aware-hierarchical-work-stealing.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [ulisp/lib/ulisp/concurrency/passes/inline_hotpath.sld](../../../ulisp/lib/ulisp/concurrency/passes/inline_hotpath.sld): R7RS ライブラリ定義 `(ulisp concurrency passes inline-hotpath)`
- [x] [ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm](../../../ulisp/lib/ulisp/concurrency/passes/pass_inline_hotpath.scm):
  - 型環境追跡機構 `hotpath-type-env`（静的型確定シンボルの収集・伝播）
  - 冗長型検査消去変換ルーチン `eliminate-redundant-type-checks`
  - 並行プリミティブ・インライン展開ルーチン `inline-concurrency-primitives`
  - プラガブルコンパイラパス注入記述子 `synapse-inline-hotpath-descriptor`, `inject-synapse-inline-hotpath-pass!`, `remove-synapse-inline-hotpath-pass!`
- [x] [ulisp/Makefile](../../../ulisp/Makefile):
  - `inline_hotpath.sld` および `pass_inline_hotpath.scm` の `lint_sexpr` 対象追加
  - 単体テストターゲット `test_pass_inline_hotpath` の追加
- [x] [tests/concurrency/test_pass_inline_hotpath.scm](../../../tests/concurrency/test_pass_inline_hotpath.scm):
  - 型推論・型環境追跡の正当性テスト
  - `(if (channel? ch) ...)` の静的消去テスト
  - `arena-alloc!` インライン展開 AST 構造検証テスト
  - `atomic-*` および `task-yield!` インライン展開テスト
  - セキュリティ境界（未検証動的変数への型検査残置）検証テスト
- [x] [benchmarks/concurrency/bench_microtasks.scm](../../../benchmarks/concurrency/bench_microtasks.scm): 最適化適用後のスループットおよびレイテンシ測定

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/682-nanopass-concurrency-hotpath-inlining-and-type-check-elimination`

### Step 1: 型環境解析と静的リソース型判定 (`pass_inline_hotpath.scm`)
1. アフィン線形型検査（`check-affine`）によって検証済みの AST を走査し、静的に型が確定している変数を追跡する環境 `type-env`（alist: `symbol -> 'channel | 'arena | 'atomic-box | 'task-context`）を構築:
   - 引数パターン規則: `linear-variable?`（`chan*`, `rx*`, `tx*`, `buf*`, `*-ch` 等）は `'channel` または `'linear-resource` として登録。
   - レキシカル束縛規則: `(let ((c (make-channel ...))) ...)` は `c` を `'channel`、`(let ((a (make-ephemeral-arena ...))) ...)` は `a` を `'arena`、`(let ((b (make-atomic-box ...))) ...)` は `b` を `'atomic-box` と静的型付け。
2. 静的型判定述語:
   - `(statically-typed-as? env sym expected-type)`: 指定されたシンボルが `expected-type` であることが保証されているかを $O(1)$ 判定。

### Step 2: 冗長型アサーション消去 (`eliminate-redundant-type-checks`)
1. AST 中の条件分岐パターンを検出し、型が静的に証明されている場合に簡約:
   - パターン 1 (正のアサーション):
     ```scheme
     (if (channel? ch) then-expr else-expr)
     ```
     `ch` が `type-env` 上で `'channel` の場合、直ちに `then-expr` へ置換（`else-expr` をデッドコードとして消去）。
   - パターン 2 (負のアサーションガード):
     ```scheme
     (if (not (channel? ch)) (error ...) body)
     ```
     `ch` が `'channel` の場合、エラーハンドラ式を完全消去し、直接 `body` に展開。
   - 同様に `(ephemeral-arena? arena)`, `(atomic-box? box)` 等も安全に消去。

### Step 3: ホットパス・並行プリミティブのインライン展開 (`inline-concurrency-primitives`)
1. **`arena-alloc!` インライン展開**:
   - `(arena-alloc! arena size)` を検出し、高速バンプ加算コードへ置換:
     ```scheme
     (let* ((%%arena arena)
            (%%sz size)
            (%%chunk (vector-ref %%arena 1))
            (%%bump (vector-ref %%chunk 1))
            (%%cap (vector-ref %%chunk 0))
            (%%new-bump (+ %%bump %%sz)))
       (if (<= %%new-bump %%cap)
           (begin
             (vector-set! %%chunk 1 %%new-bump)
             (+ (vector-ref %%chunk 2) %%bump))
           (%arena-alloc-chunk-slowpath! %%arena %%sz)))
     ```
   - チャンク境界チェック（`<= %%new-bump %%cap`）を保持し、通常時は関数呼び出しなしで 5 命令でポインタを返却。
2. **`atomic-ref` / `atomic-set!` インライン展開**:
   - `(atomic-ref box)` を直接 `%atomic-ref-raw` または `(vector-ref box 0)` へ置換。
   - `(atomic-set! box val)` を直接 `%atomic-set-raw!` へ置換。
3. **`task-yield!` インライン展開**:
   - `(task-yield!)` をタスクリダクションカウンタ判定式へ展開:
     ```scheme
     (let ((%%t current-task))
       (if (<= (task-reductions %%t) 0)
           (%task-yield-slowpath! %%t)
           (task-reductions-set! %%t (- (task-reductions %%t) 1))))
     ```

### Step 4: Nanopass パイプライン統合 (`inline_hotpath.sld`)
1. パス適用順序:
   ```
   1. pass-synapse-split-planes (ホスト/計算プレーン分離)
   2. pass-synapse-check-affine (アフィン線形性検証・RAIIドロップ挿入)
   3. pass-synapse-fbip (Perceus 原位置インプレース再利用)
   4. pass-synapse-inline-hotpath (NEW: 冗長型検査消去 & ホットパスインライン)
   5. pass-synapse-inject-safepoints (セーフポイント挿入)
   ```
2. `(inject-synapse-inline-hotpath-pass!)` によりコンパイラパスリストへ自動登録。

### Step 5: セキュリティ・堅牢性設計 (STRIDE / CWE 防止)
- **CWE-843 (Type Confusion)**:
  - 型検査の除去は、レキシカルスコープ内で生成されたことが自明な変数（`make-channel`, `make-ephemeral-arena`）および `linear-variable?` 規則に完全に合致する引数のみに限定。
  - 動的引数（`any`, `obj` 等）や未知の外部参照については、既存の動的型検査を 100% 残置するフェイルセーフ設計を徹底。
- **CWE-119 (Buffer Overflow)**:
  - インライン展開された `arena-alloc!` においても、チャンク上限（`%%cap`）に対するバウンドチェックを必ずインライン保持し、超過時は安全にスローパスへディスパッチ。
- **CWE-362 (Race Condition)**:
  - アトミック操作のインライン展開時も、x86-64 のハードウェアロックセマンティクス（`LOCK` プレフィックスおよびメモリフェンス）を厳格に保持。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `(ulisp concurrency passes inline-hotpath)` ライブラリおよび `pass_inline_hotpath.scm` が実装されていること。
- [x] `type-env` が静的型情報を正確に追跡し、型確定シンボルの判定が正常に行われること。
- [x] アフィン検証済みコードにおいて、冗長な `(if (channel? ch) ...)` や `(if (not (channel? ch)) ...)` が AST 上で完全に消去されること。
- [x] 未検証・動的型の変数に対する型検査は除去されず安全に残置されること (CWE-843 ガード)。
- [x] `arena-alloc!` および `atomic-*` がアセンブリ/LIR 親和性の高い高速インライン形式へ変換されること。
- [x] `tests/concurrency/test_pass_inline_hotpath.scm` が新規作成され、全テストケースが 100% PASS すること。
- [x] 既存の全 Nanopass パステスト群（`test_pass_split_planes`, `test_pass_check_affine`, `test_pass_fbip`, `test_pass_inject_safepoints`）が 100% PASS すること。
- [x] S式構文バランス検査（`lint_sexpr`）、Python 静的解析（`mypy --strict src`）が 100% PASS すること。
- [x] ドキュメント内の全内部リンクが相対パスであり、絶対パス（`file:///` 等）が 0 件であること。
- [x] `docs/issues/README.md` のステータスが `In Progress` に更新されていること。



---

## 6. 検証結果サマリー / Verification Results Summary

### 6.1 テスト結果
| テストスイート | 結果 |
| :--- | :---: |
| `test_pass_inline_hotpath`（新規） | **49 / 49 PASS** |
| `test_pass_split_planes` | 35 / 35 PASS |
| `test_pass_check_affine` | 35 / 35 PASS |
| `test_pass_fbip` | 23 / 23 PASS |
| `test_pass_inject_safepoints` | 28 / 28 PASS |
| `test_scheduler` / `test_multithread_scheduler` / `test_channel` / `test_atomic` | 150 / 29 / 221 / 50 PASS |
| `test_concurrency_harness` | 100 iterations, 13,100 assertions, 0 failed |
| `lint_sexpr` | 157 files balanced |
| `mypy --strict src` | 617 files, 0 issues |

### 6.2 実装時に追加したセキュリティ強化 (CWE-843 / CWE-190)
- **型付けの根拠を限定**: 名前ヒューリスティック（`box`, `arena` 等）による型付けは、`check-affine` が検証済みの **`%asc-kernel` 仮引数のみ** に適用。ローカル `let` / `let*` 束縛はコンストラクタ由来（`make-channel`, `make-task-arena`, `make-atomic-box` 等）の場合のみ型付けし、`(let ((box 5)) ...)` のような誤推論を排除。
- **スコープのシャドウイング**: `let` / `let*` / 名前付き `let` / `lambda`（可変長引数含む）の内側束縛は外側の型情報を必ず隠蔽し、同名変数による誤った型検査除去を防止。
- **サイズ検査の保持**: インライン化した `arena-allocate!` でも `(and (integer? sz) (> sz 0) (<= sz 1048576))` を保持し、不正サイズは完全検査付きのスローパスへ委譲（CWE-190）。容量上限チェックも保持（CWE-119）。
- **パス順序の決定性**: `inject-synapse-inline-hotpath-pass!` / `inject-synapse-safepoints-pass!` のどちらを先に呼んでも `fbip → inline-hotpath → inject-safepoints` の順序になることをテスト（7.2〜7.6）で保証。

### 6.3 ベンチマークに関する注記
> [!NOTE]
> 本パスは `%asc-kernel` AST を対象とするプラガブル Nanopass であり、現時点の `bench_microtasks` のビルド経路（`ulisp-boot` による直接 AOT コンパイル）にはまだ組み込まれていない。そのため実測値はパス導入前とほぼ同等（約 299 ns/task、3.34M tasks/sec）であり、概要に記載した「200 ns/task 未満 / 500 万 tasks/sec 超」の目標は **本 Issue では未達**。AOT ドライバへのパス組み込みと実測による効果検証は後続 Issue で扱う。

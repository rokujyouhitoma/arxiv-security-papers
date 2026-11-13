---
ID: 808
種別: Feature
優先度: High
ステータス: Open (In Progress)
---

# [FEAT/ENH] safepoint 有効化状態でのプリエンプション実機統合テストの追加と Makefile 除外設定の整理 (ID: 808)

## 1. 概要 / Summary

Issue #796 により `pass-synapse-inject-safepoints` が本番パイプライン (`FRONTEND_PASSES`) に組み込まれたが、`ulisp/Makefile` の33箇所で依然として `(!disable-pass pass-synapse-inject-safepoints)` が指定されており、並行処理テスト全般、stdlib、コンパイラブートストラップ等でsafepoint注入が無効化されている。

さらに、既存のプリエンプションテスト (`tests/concurrency/test_preemption.scm` の Group 9 および Group 10) では、コンパイラによる自動注入ではなく**手書きの `(%synapse-safepoint-poll!)`** をループ内に直接埋め込んでテストしており、同時に Makefile 側で `(!disable-pass pass-synapse-inject-safepoints)` が指定されている。その結果、**手動 poll を一切含まない純粋な Scheme ループが、コンパイラによって自動注入された safepoint によりリンク先タスクからの `kill` / `task-handle-termination!` で確実に強制停止・リソース回収されることを検証する動的実機テストが1件も存在しない**状態となっている。

本 Issue では以下の2点を完遂する：
1. **純粋な Scheme ループに対する動的実機プリエンプション統合テストの確立**:
   手動 poll を一切書かない通常の再帰ループ (`let loop`) を、`pass-synapse-inject-safepoints` 有効化状態でコンパイルし、リンクされたピアタスクの異常終了または `kill` により、指定回数（例: 5反復目）で即座に脱出継続 (`task-escape-continuation`) 経由でループが中断され、Arena リソースが安全に回収されることを実機（Linux x86-64）上で動的検証する。
2. **Makefile における `(!disable-pass pass-synapse-inject-safepoints)` の全33箇所監査と段階的整理**:
   「自立型ブートストラップ／stdlib で必須の除外設定」と「暫定的に除外されていた並行性テスト群」を明確に分類し、並行性テスト群においてセーフポイント注入を安全に有効化・整理する。

---

## 2. トレーサビリティ / Traceability

- **設計仕様書**:
  - [DSN-37 Synapse Concurrency Architecture Specification Section 7.2 & 14.4](../../docs/design/DSN-37-synapse-concurrency-architecture-specification.md)
  - [DSN-33 Nanopass Architecture Section 6](../../docs/design/DSN-33-nanopass-aot-compiler-architecture.md)
- **関連 Issue**:
  - [Issue #796 (セーフポイント注入パスの本番コンパイラ PASSES パイプライン正式統合)](closed/796-integrate-pass-inject-safepoints-into-compiler-passes-pipeline.md)
  - [Issue #790 (自動セーフポイント挿入による強制終了テスト)](closed/790-add-safepoint-forced-exit-tests.md)
  - [Issue #799 (クロスワーカー環境テスト拡充および Linux 実機 CI 検証環境の確立)](closed/799-add-cross-worker-coroutine-yield-exception-and-linux-ci-stress-tests.md)
  - [Issue #802 (セーフポイント注入時における末尾呼び出し最適化 (TCO) の保護)](closed/802-preserve-tail-call-optimization-in-safepoint-injection.md)
  - [Issue #807 (x86-64 バックエンドにおけるセーフポイントポーリング stub 重複定義の解消)](closed/807-eliminate-duplicate-safepoint-poll-stub-in-x86-64-backend.md)
  - [Issue #809 (%synapse-safepoint-poll! の LIR コード未生成の修正および aarch64 向けスタブの提供)](809-fix-safepoint-poll-lir-code-emission-and-add-aarch64-stub.md)
  - [Issue #810 (safepoint 挿入除外判定の名前プレフィックス廃止と declare no-safepoints 構文の導入)](810-deprecate-name-prefix-safepoint-exclusion-and-introduce-declare-no-safepoints.md)

---

## 3. 多角的多重エージェント審議レビュー / Multi-Agent Architectural Review

1. **Project Manager (PM) (Chair)**:
   - 手動 poll 依存のテストは「コンパイラによる自動注入パスの保証」になっておらず、回帰バグを見逃す重大なリスクがある。実機統合テストの追加と Makefile の精査を最優先で推進する。
2. **Systems Architect (SA)**:
   - `pass-synapse-inject-safepoints` は AST 上の `lambda` および `named-let` に対し `(%synapse-safepoint-poll!)` を注入する。ブートストラップコンパイラ (`compiler_input.scm`, `stdlib_input.scm`) はランタイムの `current-synapse-task` を持たない自給自足バイナリであるため除外を維持する必要があるが、高レベル並行性テスト群は safepoint 有効化が本来の姿である。
3. **Information Security Specialist (ISS)**:
   - **CWE-400 (不制御なリソース消費 / CPU 枯渇)**: 無限ループや暴走した悪意あるタスクがスレッドを独占する DoS 攻撃を防ぐには、コンパイラレベルでセーフポイントが不可避に埋め込まれていることが必須。
   - **CWE-703 (例外条件の不適切な処理)**: リンクされた監視先／ピアタスクがクラッシュした際、生存タスクがセーフポイントで即座に脱出しないと不正な状態のまま後続処理が走る。脱出継続 (`task-escape-continuation`) の即時発火を実機で実証せよ。
4. **Software Quality Assurance (SQA)**:
   - テストスイート内で手動 poll を排除した「純粋な Scheme ループ (Group 11)」を作成し、100% の再現性で 5 反復目の中断を assert すること。また、Makefile の整理前後で既存テスト（92項目）が全て PASS することを検証する。
5. **IT Specialist (Programming Languages & Compilers / PLC)**:
   - `pass-synapse-inject-safepoints` の除外プレフィックス (`*safepoint-excluded-prefixes*`) に合致しない関数やラムダは全て safepoint が注入される。テスト内の高反復ベンチマークループ（Group 4 や Group 6）に過大なオーバーヘッドが生じないよう、テスト設計またはプレフィックス・アノテーションを吟味すること。
6. **Software Development (SWD)**:
   - `test_preemption.scm` に Group 11 を追加し、`test_preemption` のビルド規則から `(!disable-pass pass-synapse-inject-safepoints)` を安全に除去する手順を確立する。
7. **IT Service Manager (ITSM)**:
   - CI および `make test` においてコンパイル時間および実行時間が 10 秒を超過しない SLA を遵守すること。
8. **Systems Auditor**:
   - 全 33 箇所の除外設定について「なぜ除外を維持するか」「なぜ除外を解除したか」を本 Issue およびドキュメントに明記し、完全な説明責任とトレーサビリティを担保すること。

---

## 4. セキュリティ・プリエンプション健全性設計 / Security & Integrity Analysis

| 脅威 / リスク | CWE 分類 | 潜在的影響 | 本 Issue での対策・検証 |
| :--- | :--- | :--- | :--- |
| **CPU 独占 / Starvation** | CWE-400 | 手動 poll のない計算集約タスクがワーカーを占有し他タスクが飢餓 | コンパイラがループ後方枝に自動注入したセーフポイントが減算バジェットを消費し、プリエンプション可能であることを実証 |
| **孤立タスクの暴走実行** | CWE-703 | リンク元が死亡しても手動 poll がないため survivor タスクが停止せず不正動作 | 外部 `task-handle-termination!` 発行時に、自動注入 safepoint が直ちに脱出継続を起動してタスクを中断 |
| **メモリリーク / リソース解放漏れ** | CWE-401 | プリエンプト脱出時にタスク Arena が回収されずリーク | 脱出後に `task-arena-reset!` または Arena 回収処理が確実に実行され 0 バイトに戻ることを検証 |
| **スタックオーバーフロー (TCO 破壊)** | CWE-674 | safepoint 注入により末尾呼び出しが非末尾化してスタック枯渇 | Issue #802 で検証された TCO 保護が実機テスト下でも維持されることを確認 |

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [ulisp/Makefile](../../ulisp/Makefile) (33 箇所の `(!disable-pass pass-synapse-inject-safepoints)` 監査と整理)
- [ ] [tests/concurrency/test_preemption.scm](../../tests/concurrency/test_preemption.scm) (Group 11: 自動注入セーフポイントによる動的強制終了テストの追加)
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm) (必要に応じたプレフィックス・除外ロジックの確認)
- [ ] [ulisp/runtime/concurrency/preempt.scm](../../ulisp/runtime/concurrency/preempt.scm) (`(%synapse-safepoint-poll!)` 呼び出し経路の確認)
- [ ] [docs/issues/README.md](README.md) (Issue 台帳更新)

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/808-add-hardware-safepoint-preemption-tests`

### Phase 1: `ulisp/Makefile` の 33 箇所除外設定の全数監査と分類
`ulisp/Makefile` 内で `(!disable-pass pass-synapse-inject-safepoints)` が指定されている 33 箇所を以下の 3 カテゴリに正式分類する：
1. **Category A: ブートストラップ＆スタンドアロン実行体（除外維持必須: 5箇所）**
   - `build/stdlib_input.scm` (1226行目)
   - `build/stdlib_aarch64_input.scm` (1236行目)
   - `build/compiler_input.scm` (1246行目)
   - `test_split` (1260行目)
   - `build/compiler_driver_in.scm` (1331行目)
   - *理由*: コンパイラ自身および標準ライブラリは、並行性ランタイム (`current-synapse-task`) とリンクされない独立基盤であり、safepoint を注入すると未定義シンボル参照または不要なオーバーヘッドとなるため、除外を永続的に維持する。
2. **Category B: スタンドアロン I/O・数値演算・低レベル単体テスト（除外維持または整理検討: 7箇所）**
   - `test_reader_eof` (783行目), `test_ports` (1131行目), `test_numeric_tower` (1582行目)
   - `test_runtime` (260行目), `test_arena` (269行目), `test_atomic` (278行目), `test_futex` (415行目)
   - *理由*: タスクコンテキストを持たない純粋な C ABI / メモリアロケータ等の低レベルテスト。
3. **Category C: 並行性・スケジューラ・タスク間通信テスト（解除ターゲット: 21箇所）**
   - `test_preemption` (451行目) ★本 Issue の主対象
   - `test_queue`, `test_channel`, `test_boundary`, `test_epoch`, `test_context_switch`, `test_scheduler`, `test_multithread_scheduler`, `test_links_monitors`, `test_task_mailbox`, `test_let_it_crash`, `test_supervisor`, `test_registry`, `test_crash_logger`, `test_io_uring`, `test_eval_adapter`, `test_concurrency_harness`
   - マイクロベンチマーク群 (`bench_microtasks`, `bench_latency_under_gc`, `bench_microtasks_threaded`, `bench_microtasks_multi`)

### Phase 2: `tests/concurrency/test_preemption.scm` に Group 11 実機テストを追加
手書きの `(%synapse-safepoint-poll!)` を一切呼ばない純粋な R7RS Scheme ループを定義：
```scheme
;; -----------------------------------------------------------------------
;; Group 11: True Dynamic Preemption with Compiler-Injected Safepoints (#808)
;; -----------------------------------------------------------------------
(write-string "--- Group 11: Dynamic Injected Safepoint Preemption (#808) ---\n")

(let* ((t-killer3 (make-task-context))
       (t-worker3 (make-task-context))
       (worker-arena3 (make-task-arena 2048))
       (pure-worker-iters (vector 0)))
  (task-set-arena! t-worker3 worker-arena3)
  (task-link! t-killer3 t-worker3)

  ;; Pure loop WITHOUT any manual (%synapse-safepoint-poll!) calls:
  ;; Rely 100% on pass-synapse-inject-safepoints compiler pass.
  (let ((res (with-synapse-task-boundary t-worker3
               (lambda ()
                 (let pure-loop ((count 0))
                   (if (< count 1000000)
                       (begin
                         (vector-set! pure-worker-iters 0 (+ (vector-ref pure-worker-iters 0) 1))
                         (if (= count 5)
                             (task-handle-termination! t-killer3 'peer_fault)
                             #f)
                         (pure-loop (+ count 1)))
                       'completed-1m))))))
    (assert-equal (task-state t-worker3) 'terminated "pure worker task transitioned to 'terminated via injected safepoint")
    (assert-equal (task-reductions t-worker3) 0 "pure worker reductions zeroed upon termination")
    (assert-equal (vector-ref pure-worker-iters 0) 6 "pure loop stopped immediately at count 5/6 (not 1,000,000)")
    (assert-equal (car res) 'terminated "task boundary returned 'terminated from compiler-injected safepoint")
    (assert-equal (arena-used-bytes worker-arena3) 0 "task arena reclaimed after safepoint exit")))
```

### Phase 3: `ulisp/Makefile` の `test_preemption` における `disable-pass` 解除と調整
1. `ulisp/Makefile` 451行目の `test_preemption` ルールから `(!disable-pass pass-synapse-inject-safepoints)` を削除。
2. `test_preemption.scm` 内の既存テスト（特に Group 4 の 50,000 回ループなど、スケジューラ非協調ループ）が safepoint 注入により過大な再スケジュール再帰を起こさないよう、テスト関数の命名または適切なバジェット・反復数へ最適化。
3. `make -C ulisp test_preemption` を実行し、全 97+ 項目が PASS することを確認。

### Phase 4: 他の並行性テストへの段階的適用検証
1. `test_links_monitors`, `test_let_it_crash`, `test_supervisor` 等の主要テストから段階的に `(!disable-pass pass-synapse-inject-safepoints)` を解除し、動作検証を行う。
2. 問題なく動作するものは除外を恒久解除し、Makefile をクリーンアップする。

### Phase 5: 品質ゲート検証とコミット
1. `make test` または `make -C ulisp test_concurrency` の全 PASS を確認。
2. `make py_compile && make static_analysis` の PASS を確認。
3. `docs/issues/README.md` を更新し、コミットを作成。

---

## 7. 完了条件 / Definition of Done (DoD)

- [ ] `tests/concurrency/test_preemption.scm` に手動 poll を含まない「純粋な Scheme ループ」の動的実機テスト (Group 11) が追加されていること。
- [ ] `ulisp/Makefile` の `test_preemption` ビルドターゲットにおいて `(!disable-pass pass-synapse-inject-safepoints)` が除去され、コンパイラ自動注入が有効化されていること。
- [ ] 外部 `task-handle-termination!`（ピア異常終了）によって、純粋なループが脱出継続経由で確実に中断され、Arena リソースが 0 バイトに回収されることがテストで実証されること。
- [ ] `ulisp/Makefile` 内の 33 箇所の除外設定が精査・分類され、不要な除外が削減されていること。
- [ ] `make -C ulisp test_preemption` および関連テストが全件 PASS すること。
- [ ] ドキュメント内の全リンクが 100% 相対パスであること。
- [ ] `docs/issues/README.md` のステータスが更新されていること。

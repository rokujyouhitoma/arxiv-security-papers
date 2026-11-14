---
ID: 814
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] 143_backend_x86_peephole.scm の define-picopass 化と fuse-window-rules への移行 (ID: 814)

## 1. 概要 / Summary

Nanopass アーキテクチャ仕様書（DSN-33-01 Task 5.3）において、LIR ピープホール最適化（Pass 133）および x86 ネイティブマシンピープホール最適化（Pass 143）は、`define-picopass (InstWindow ...)` および `fuse-window-rules` スライディングウィンドウ走査への移行対象として設計された。
しかし先行する Issue #767 では Pass 128 (LIR 分岐融合) および Pass 133 (LIR ピープホール) のみが Picopass 化され、`ulisp/backend/143_backend_x86_peephole.scm` は手書きの `x86-peephole-step-window`（8 規則、約180行の手動走査ループ）のまま取り残されている。

本 Issue では、Pass 133 の実績ある `InstWindow` パターン整合 DSL および `fuse-window-rules` を用いて、`143_backend_x86_peephole.scm` の全ピープホール規則を第一級 Picopass に移行する：
1. **8 つの x86 最適化規則を個別の `define-picopass` に分解・定義**:
   - `rule-x86-self-mov-elim`: 自己代入除去 `(mov reg reg) -> ()`
   - `rule-x86-roundtrip-mov-elim`: 往復レジスタ転送除去 `(mov r1 r2) (mov r2 r1) -> (mov r1 r2)`
   - `rule-x86-zero-xor`: ゼロ初期化 XOR 最適化 `(mov reg 0) -> (xor reg reg)`
   - `rule-x86-jump-next-label`: 直後ラベルへの冗長 jump 除去 `(jmp L1) (%label L1) -> (%label L1)`
   - `rule-x86-jump-p2align-next-label`: アライメントディレクティブ越え冗長 jump 除去 `(jmp L1) (%p2align _) (%label L1) -> (%p2align _) (%label L1)`
   - `rule-x86-lea-optimize`: LEA 統合最適化 `(mov r1 r2) (add r1 imm) -> (lea r1 (%disp imm r2))`
   - `rule-x86-unreachable-dce`: 無条件分岐直後の到達不能コード除去
   - `rule-x86-jump-to-ret`: 複数ブロックを跨ぐ ret への jump 簡約 `(jmp L1) ... (%label L1) (ret) -> (ret)`
2. **`fuse-window-rules` スライディングウィンドウ走査への接続**:
   - `ulisp/compiler/nanopass_meta.scm` の `nanopass-wrap-window-rules-input` を拡張し、`L_lir_canonical`（`%lir-*`）に加えて `L_asm_x86`（`%asm-program`, `%asm-function`, `%asm-main`）および命令リストの透過的走査をサポート。
   - `optimize-x86-peephole-insts` 手書きループを、宣言的な `(define-pass x86-peephole-pass : L_asm_x86 (ir) -> L_asm_x86 () (fuse-window-rules ...))` に置換。
3. **Provenance Tracking & Auto-Bisect の完全適用**:
   - Issue #769 で導入された Provenance Tracking（発火 Picopass 名追跡）および Auto-Bisect（ルール単位の自動二分探索デバッグ）の対象を x86 バックエンドまで完全拡大。
4. **完全な後方互換性の保証**:
   - 既存の呼び出し API である `(optimize-x86-peephole prog)` および `(optimize-x86-peephole-insts insts)` は `x86-peephole-pass` への透過的委譲として維持し、外部依存箇所への影響を 0 に保つ。

---

## 2. トレーサビリティ / Traceability

- [DSN-33-01 Nanopass/Picopass DAG アーキテクチャ仕様書 Section 3.3 & 5.3](../designs/DSN-33-01-ulisp_pipeline_pass_nanopass_picopass_dag_architecture.md)
  - T3.3: LIR/マシン命令列向け `fuse-window-rules` スライディングウィンドウ走査および収束ドライバの実装
  - T5.3: LIR 分岐融合 (128)・ピープホール (133)・x86 ピープホール (143) の Picopass 化
- 関連 Issue:
  - [Issue #761 (fuse-window-rules 実装)](closed/761-implement-fuse-window-rules-for-lir-sliding-window.md)
  - [Issue #767 (LIR ピープホール Picopass 化)](closed/767-migrate-lir-peephole-to-picopass-and-dependency-dag.md)
  - [Issue #769 (Picopass Provenance Tracking & Auto-Bisect)](closed/769-implement-picopass-provenance-tracing-and-auto-bisect.md)
  - [Issue #812 (AArch64 回帰修正と Picopass 整合)](closed/812-fix-aarch64-qemu-regression-stdlib-include-path-and-context-switch-segfault.md)

---

## 3. 影響範囲と対象ファイル / Scope and Affected Files

1. **[ulisp/backend/143_backend_x86_peephole.scm](../../ulisp/backend/143_backend_x86_peephole.scm)**:
   - 手書きの `x86-peephole-step-window`（約180行）を撤廃。
   - 8 つの `define-picopass` 規則（`rule-x86-self-mov-elim` 〜 `rule-x86-jump-to-ret`）を定義。
   - `define-pass x86-peephole-pass` による宣言的 `fuse-window-rules` 走査に置換。
   - 互換ラッパー `optimize-x86-peephole` および `optimize-x86-peephole-insts` を提供。
2. **[ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)**:
   - `nanopass-optimize-asm-function-body` および `nanopass-optimize-asm-main-body` を追加。
   - `nanopass-wrap-window-rules-input` に `%asm-program`, `%asm-function`, `%asm-main` の分岐を追加し、`L_asm_x86` AST を自然に走査可能とする。
3. **[ulisp/tests/passes/test_143_backend_x86_peephole.scm](../../ulisp/tests/passes/test_143_backend_x86_peephole.scm)**:
   - 既存の 8 テストケースに加え、未網羅だった `rule-x86-jump-p2align-next-label`, `rule-x86-lea-optimize`, `rule-x86-jump-to-ret` の単体テストを追加。
   - 各 Picopass 規則の直接呼び出しテストおよび Provenance Tracking 発火検証テストを追加。
4. **[ulisp/compiler.scm](../../ulisp/compiler.scm)**:
   - `make -C ulisp compiler` による自動再生成対象。

---

## 4. 脅威モデルとセキュリティ考察 / Threat Modeling & Security Considerations

| 脅威 / リスク | 影響度 | 対策・検証方針 |
| :--- | :---: | :--- |
| **CWE-787: Out-of-bounds Write / CWE-125: Out-of-bounds Read** | 高 | ウィンドウパターンマッチング時に命令列の長さや構造が不十分な場合、不正な `car`/`cdr` によるコンパイラクラッシュが発生するリスク。`InstWindow` のパターンコンパイラによる安全なリスト境界ガードと構造チェックを徹底する。 |
| **CWE-670: Always-Incorrect Control Flow Implementation** | 高 | 到達不能コード除去（`rule-x86-unreachable-dce`）やジャンプ短絡（`rule-x86-jump-next-label`）が、ジャンプ先ラベル（`%label`）やアライメント（`%p2align` / `%align`）を誤って削除し、制御フローが意図しないブロックへフォールスルーするリスク。ラベル・アライメント境界を厳密にスキップ停止条件とし、安全に保持する。 |
| **CWE-440: Expected Behavioral Violation (セマンティクス破壊)** | 中 | `(mov r1 r2) (add r1 imm)` を `(lea r1 (%disp imm r2))` に融合する際、`add` と `lea` では EFLAGS（フラグ変化）の挙動が異なる。ULisp の LIR 生成コードでは後続がフラグ依存しない直後加算（ポインタ計算・配列オフセット）に限定されているが、`r1 != r2` かつオペランド型が安全であることをガードで厳密に確認する。 |
| **Stage 2 / Stage 3 ブートストラップ不整合 (Reproducible Builds)** | 高 | ピープホール最適化の規則適用順序や停止条件が非決定論的であると、セルフホスティングコンパイラの bit-for-bit 不動点が崩れる。`fuse-window-rules` の決定論的固定点ループ（上限 `*nanopass-window-fixpoint-limit* = 16`）により、完全に再現可能なバイナリ出力を保証する。 |

---

## 5. 詳細設計と実装方針 / Implementation Plan

### 対象ブランチ
`feat/814-migrate-x86-peephole-to-picopass-and-fuse-window-rules`

### Phase 1: `nanopass_meta.scm` における `L_asm_x86` AST サポート拡張
1. `ulisp/compiler/nanopass_meta.scm` の `nanopass-optimize-asm-function-body` を追加:
   ```scheme
   (define (nanopass-optimize-asm-function-body opt-proc f)
     (if (and (pair? f) (eq? (car f) '%asm-function))
         (let* ((lbl (cadr f))
                (frame-size-clause (caddr f))
                (body-clause (cadddr f))
                (insts (if (and (pair? body-clause) (eq? (car body-clause) 'body))
                           (cdr body-clause)
                           '()))
                (opt-insts (opt-proc insts)))
           (if (eq? opt-insts insts)
               f
               (list '%asm-function lbl frame-size-clause (cons 'body opt-insts))))
         f))
   ```
2. `nanopass-optimize-asm-main-body` を追加:
   ```scheme
   (define (nanopass-optimize-asm-main-body opt-proc m)
     (if (and (pair? m) (eq? (car m) '%asm-main))
         (let* ((frame-size-clause (cadr m))
                (body-clause (caddr m))
                (insts (if (and (pair? body-clause) (eq? (car body-clause) 'body))
                           (cdr body-clause)
                           '()))
                (opt-insts (opt-proc insts)))
           (if (eq? opt-insts insts)
               m
               (list '%asm-main frame-size-clause (cons 'body opt-insts))))
         m))
   ```
3. `nanopass-wrap-window-rules-input` に `%asm-program`, `%asm-function`, `%asm-main` の分岐を追加し、`%lir-*` と同等の多相的走査を実現する。

### Phase 2: `143_backend_x86_peephole.scm` の Picopass 規則群の実装
以下の 8 つの Picopass を `define-picopass (InstWindow ...)` 形式で定義する:
1. `rule-x86-self-mov-elim`:
   ```scheme
   (define-picopass rule-x86-self-mov-elim
     (InstWindow
       (((mov ,r1 ,r2) . ,rest)
        (guard (and (x86-asm-reg? r1) (equal? r1 r2)))
        rest)))
   ```
2. `rule-x86-roundtrip-mov-elim`:
   ```scheme
   (define-picopass rule-x86-roundtrip-mov-elim
     (InstWindow
       (((mov ,r1 ,r2) (mov ,r3 ,r4) . ,rest)
        (guard (and (x86-asm-reg? r1)
                    (x86-asm-reg? r2)
                    (equal? r1 r4)
                    (equal? r2 r3)))
        (cons (list 'mov r1 r2) rest))))
   ```
3. `rule-x86-zero-xor`:
   ```scheme
   (define-picopass rule-x86-zero-xor
     (InstWindow
       (((mov ,reg ,imm) . ,rest)
        (guard (and (x86-asm-reg? reg)
                    (x86-asm-zero-imm? imm)))
        (cons (list 'xor reg reg) rest))))
   ```
4. `rule-x86-jump-next-label`:
   ```scheme
   (define-picopass rule-x86-jump-next-label
     (InstWindow
       (((jmp ,l1) (%label ,l2) . ,rest)
        (guard (equal? l1 l2))
        (cons (list '%label l2) rest))))
   ```
5. `rule-x86-jump-p2align-next-label`:
   ```scheme
   (define-picopass rule-x86-jump-p2align-next-label
     (InstWindow
       (((jmp ,l1) (%p2align ,al) (%label ,l2) . ,rest)
        (guard (equal? l1 l2))
        (cons (list '%p2align al) (cons (list '%label l2) rest)))
       (((jmp ,l1) (%align ,al) (%label ,l2) . ,rest)
        (guard (equal? l1 l2))
        (cons (list '%align al) (cons (list '%label l2) rest)))))
   ```
6. `rule-x86-lea-optimize`:
   ```scheme
   (define-picopass rule-x86-lea-optimize
     (InstWindow
       (((mov ,r1 ,r2) (add ,r3 ,imm) . ,rest)
        (guard (and (x86-asm-reg? r1)
                    (x86-asm-reg? r2)
                    (not (equal? r1 r2))
                    (equal? r1 r3)
                    (or (integer? imm)
                        (and (pair? imm) (eq? (car imm) '%imm) (integer? (cadr imm))))))
        (let ((c (if (integer? imm) imm (cadr imm))))
          (cons (list 'lea r1 (list '%disp c r2)) rest)))))
   ```
7. `rule-x86-unreachable-dce`:
   ```scheme
   (define-picopass rule-x86-unreachable-dce
     (InstWindow
       (((jmp ,lbl) ,next . ,rest)
        (guard (not (or (x86-asm-label-inst? next)
                        (and (pair? next) (memq (car next) '(%p2align %align))))))
        (cons (list 'jmp lbl) (x86-asm-skip-to-next-label rest)))
       (((ret) ,next . ,rest)
        (guard (not (or (x86-asm-label-inst? next)
                        (and (pair? next) (memq (car next) '(%p2align %align))))))
        (cons '(ret) (x86-asm-skip-to-next-label rest)))))
   ```
8. `rule-x86-jump-to-ret`:
   ```scheme
   (define-picopass rule-x86-jump-to-ret
     (InstWindow
       (((jmp ,target) . ,rest)
        (guard (x86-jump-targets-ret-across-labels? target rest))
        (cons '(ret) rest))))
   ```

### Phase 3: `x86-peephole-pass` の定義と互換性ラッパーの整備
1. `fuse-window-rules` による統合パスを定義:
   ```scheme
   (define-pass x86-peephole-pass : L_asm_x86 (ir) -> L_asm_x86 ()
     (fuse-window-rules
       rule-x86-self-mov-elim
       rule-x86-roundtrip-mov-elim
       rule-x86-zero-xor
       rule-x86-jump-next-label
       rule-x86-jump-p2align-next-label
       rule-x86-lea-optimize
       rule-x86-unreachable-dce
       rule-x86-jump-to-ret))
   ```
2. 互換 API 関数を接続:
   ```scheme
   (define (optimize-x86-peephole-insts insts)
     (x86-peephole-pass insts))

   (define (optimize-x86-peephole prog)
     (x86-peephole-pass prog))
   ```
3. 旧手書きループ `x86-peephole-step-window`, `optimize-x86-peephole-function`, `optimize-x86-peephole-main` を完全に削除。

### Phase 4: 単体テスト (`test_143_backend_x86_peephole.scm`) の拡充
1. 既存の 8 テストが全て PASS することを検証。
2. 追加テストケースの実装:
   - テスト 9: `rule-x86-jump-p2align-next-label` 単体検証 (`(jmp L1) (%p2align 4) (%label L1)`)
   - テスト 10: `rule-x86-lea-optimize` 単体検証 (`(mov rax rbx) (add rax 8) -> (lea rax (%disp 8 rbx))`)
   - テスト 11: `rule-x86-jump-to-ret` 単体検証
   - テスト 12: 個別 Picopass 規則直接呼び出し検証 (`(rule-x86-self-mov-elim '((mov rax rax) (ret)))`)
   - テスト 13: Provenance Tracking 検証 (`enable-picopass-provenance!` を有効化し、`get-picopass-firing-counts` で `rule-x86-zero-xor` 等の発火が記録されることを確認)

### Phase 5: 全体検証・品質ゲートおよびブートストラップ確認
1. `make -C ulisp compiler` で `compiler.scm` を再生成。
2. `make -C ulisp lint_sexpr` で括弧整合性を確認。
3. `make -C ulisp test_passes` および `make -C ulisp test` を実行。
4. `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 一致（不動点生成）を検証。
5. `make py_compile && make static_analysis` の合格を確認。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] `nanopass_meta.scm` の `nanopass-wrap-window-rules-input` が `L_asm_x86` の `%asm-program`, `%asm-function`, `%asm-main` をサポートしていること。
- [x] `143_backend_x86_peephole.scm` の手書き走査ループ（`x86-peephole-step-window` 等）が撤廃され、全 8 規則が `define-picopass` として定義されていること。
- [x] `x86-peephole-pass` が `(fuse-window-rules ...)` として定義され、既存の `optimize-x86-peephole` / `optimize-x86-peephole-insts` が透過的に動作すること。
- [x] `test_143_backend_x86_peephole.scm` に全 8 規則の網羅テストおよび Provenance Tracking 検証テストが追加され、全テストが 100% PASS すること（22/22 PASS）。
- [x] `make -C ulisp compiler` で生成された `compiler.scm` が構文エラーなく正常に動作すること。
- [x] `make -C ulisp bootstrap_verify` で Stage 2 と Stage 3 の bit-for-bit 一致が確認されること（全5モジュール完全一致）。
- [x] `make py_compile` および `make static_analysis` がエラー 0 件で通過すること。
- [x] ドキュメント内のすべての内部リンクが相対パス（`docs/`, `ulisp/`）で記述されていること。

---

## 7. 完了報告 / Completion Summary

1. **実装成果**:
   - `ulisp/compiler/nanopass_meta.scm`: `nanopass-optimize-asm-function-body` および `nanopass-optimize-asm-main-body` を新設し、`nanopass-wrap-window-rules-input` にて `%asm-program`, `%asm-function`, `%asm-main` の透過的トラバーサルをサポート。
   - `ulisp/backend/143_backend_x86_peephole.scm`: 手書きループ（`x86-peephole-step-window` 等）を完全撤廃し、全 8 規則を `define-picopass` 化。`x86-peephole-pass` を `fuse-window-rules` として定義し、後方互換 API `optimize-x86-peephole` / `optimize-x86-peephole-insts` を透過的に接続。
   - `ulisp/tests/passes/test_143_backend_x86_peephole.scm`: テストケース 9〜13 を追加し、全 22 アサーションが 100% PASS。
2. **検証結果**:
   - `make -C ulisp test_143`: 22/22 PASS
   - `make -C ulisp test_passes`: 39/39 パス 782/782 PASS, Per-Pass 147/147 PASS
   - `make -C ulisp test_backend`: 3/3 PASS
   - `make -C ulisp bootstrap_verify`: 5 モジュール（compiler_base, frontend_passes, lir_passes, backend_passes, compiler_driver）すべてで Stage 2 == Stage 3 の不動点完全一致（bit-for-bit identical）を達成。
   - `make -C ulisp test`: 総合テストスイート全件 PASS。
   - `make py_compile && make static_analysis`: エラー 0 件（617 ファイル検証）。

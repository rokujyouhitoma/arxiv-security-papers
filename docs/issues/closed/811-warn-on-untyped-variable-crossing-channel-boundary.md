---
ID: 811
種別: Feature
優先度: Medium
ステータス: Closed
---

# [FEAT/ENH] 型推論不能な変数のチャネル境界通過時における静的コンパイル警告の導入 (ID: 811)

## 1. 概要 / Summary

Issue #797 により、split-planes パスおよびチャネル境界処理における変数名依存ヒューリスティックが撤廃され、型推論できない変数については安全側に倒して暗黙的に `deep-copy` として扱われる設計となった。
しかし、開発者がチャネルに型注釈を付け忘れた場合や、大規模なデータ構造（バッファやリスト）を意図せずクロージャキャプチャした場合でも、エラーや警告が一切出力されずに通過するため、以下の課題が生じている：
1. **暗黙的 deep-copy による性能低下 (CWE-400)**: ゼロコピー移動（`linear-move`）や即値参照を意図していた開発者が型注釈を失念した場合、実行時に全走査ディープコピーが発生し、スループットが大幅に低下する。
2. **設計ミス・競合リスクの潜伏 (CWE-843 / CWE-362)**: 線形チャネル（`channel`）として扱うべき変数を型なしで渡すと、複製されたオブジェクトが生成され、意図しないデッドロックやリソース追跡不全を引き起こす恐れがある。

本 Issue では、プロセス／チャネル境界（`spawn-task`, `with-channel`）をまたぐ変数のキャプチャ時において、型が未解決（`unknown` / `untyped`）で暗黙的に `deep-copy` にフォールバックするケースに対し、コンパイル時診断警告（`[WARN]`）を出力する機構を導入する。
あわせて、意図的なディープコピーを開発者が宣言して警告を抑制できる明示的アノテーション（`(: var deep-copy)` / `(: var any)`）およびコンパイラ制御フラグ（`*warn-untyped-boundary*` / `ULISP_WARN_UNTYPED_BOUNDARY`）を整備する。

---

## 2. トレーサビリティ / Traceability

- **先行・関連 Issue**:
  - [797-eliminate-name-based-heuristics-in-split-planes-capture-and-affine-check.md](closed/797-eliminate-name-based-heuristics-in-split-planes-capture-and-affine-check.md) (split-planes パスおよび ASC カーネルにおける変数名依存ヒューリスティックの完全撤廃)
  - [792-refactor-affine-check-to-eliminate-name-based-heuristics.md](closed/792-refactor-affine-check-to-eliminate-name-based-heuristics.md) (Affine 検査における変数名ヒント強制判定の廃止)
  - [602-enhance-compiler-diagnostics-and-source-location.md](closed/602-enhance-compiler-diagnostics-and-source-location.md) (コンパイラコンテキストと診断レポート)
  - [637-implement-synapse-dual-plane-boundary-splitting-pass.md](closed/637-implement-synapse-dual-plane-boundary-splitting-pass.md) (Synapse Dual-Plane 境界分割パス)
  - [823-unify-test-runner-output-formats-and-add-verbose-mode.md](closed/823-unify-test-runner-output-formats-and-add-verbose-mode.md) (テストランナー出力統一)
- **設計仕様書**:
  - `ulisp/docs/spec_synapse_architecture.md` (DSN-37 Section 8.1 Capture Mode Classification, Section 12.1 Boundary Safety)
  - `ulisp/docs/ref_r7rs_compliance.md` (Section 4 Compiler & Runtime Diagnostics)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files

### A. コンパイラ・並行性パス基盤 (2ファイル)
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm)
  - `*warn-untyped-boundary*` フラグおよび環境変数 `ULISP_WARN_UNTYPED_BOUNDARY` による制御機構の導入。
  - `*untyped-boundary-warnings*` 診断ログ追跡バッファおよび `(reset-untyped-boundary-warnings!)`, `(untyped-boundary-warnings)` API の追加。
  - `emit-untyped-boundary-warning`: 統一フォーマット `[WARN] pass-synapse-split-planes: Untyped variable '<var>' crossing boundary ...` の出力・記録。
  - `classify-capture-mode`:
    - 型注釈なしシンボルが `deep-copy` にフォールバックした際の警告フック呼び出し。
    - 明示的アノテーション `(: v deep-copy)` / `(: v any)` による意図的フォールバックの警告抑制。
  - `%split-spawn-task` / `%split-with-channel`: 境界コンテキスト情報の伝播。

### B. テストスイート (1ファイル)
- [ ] [tests/concurrency/test_pass_split_planes.scm](../../tests/concurrency/test_pass_split_planes.scm)
  - Group 2 に「型なし変数境界通過時の Warning 発行検証」を追加。
  - 明示的 `(: v deep-copy)` アノテーションによる警告抑制検証を追加。
  - `*warn-untyped-boundary*` / 環境変数フラグによる警告抑制検証を追加。
  - 既存の型付き変数（`count`, `idx`, `c`, `my-pipe` 等）で偽陽性警告が一切発生しないこと（Zero False Positives）を検証。

---

## 4. 脅威モデルとセキュリティ要件 (Threat Model & Security Requirements)

- **CWE-400 (Uncontrolled Resource Consumption / CPU & Memory Exhaustion)**:
  - 巨大なバッファやチャネルを誤って型なしでキャプチャすると、タスク生成ごとに暗黙のディープコピーが走り、ヒープ枯渇や GC 頻発による DoS を招く。コンパイル時警告により、開発者に意図の明示を促し過剰なコピーを防止する。
- **CWE-843 (Access of Resource Using Incompatible Type / Type Confusion)**:
  - チャネルの型注釈忘れにより、本来 `'linear-move` で排他移動すべきリソースが `'deep-copy` され、送信側と受信側で別個のインスタンスを参照する深刻なロジック障害を早期検知・防止する。
- **CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization)**:
  - 境界越境ポリシーが不透明なまま暗黙フォールバックに依存することを抑制し、Shared-Nothing アーキテクチャの厳格性を担保する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `feat/811-warn-on-untyped-variable-crossing-channel-boundary`

### Step 1: 警告制御フラグと診断履歴追跡機構の設計 (`pass_split_planes.scm`)
1. **パラメータ定義**:
   - `*warn-untyped-boundary*`: デフォルト値は環境変数 `ULISP_WARN_UNTYPED_BOUNDARY` が `"0"` でない限り `#t`。
   - `*untyped-boundary-warnings*`: 発生した警告のシンボル・コンテキストを蓄積するリスト。
   - `(reset-untyped-boundary-warnings!)`: 警告リストのクリア。
   - `(untyped-boundary-warnings)`: 蓄積された警告リストの取得。
2. **警告出力手続き**:
   ```scheme
   (define (emit-untyped-boundary-warning var boundary-kind)
     (when (and (car *warn-untyped-boundary*) (symbol? var))
       (let ((entry (cons var boundary-kind)))
         (set-car! *untyped-boundary-warnings*
                   (cons entry (car *untyped-boundary-warnings*)))
         (let ((port (current-error-port)))
           (display "[WARN] pass-synapse-split-planes: Untyped variable '" port)
           (display var port)
           (display "' crossing " port)
           (display boundary-kind port)
           (display " boundary; falling back to deep-copy. Consider annotating with (: " port)
           (display var port)
           (display " <type>) or (: " port)
           (display var port)
           (display " deep-copy).\n" port)))))
   ```

### Step 2: `classify-capture-mode` のアノテーション拡張と警告フック
1. **アノテーションの認識拡張**:
   - `(: v deep-copy)`, `(v : deep-copy)`, `(: v any)`, `(v : any)` を明示的ディープコピー指定として認識。
   - 明示的指定時は警告を発行せず、速やかに `'deep-copy` を返却。
2. **暗黙フォールバック時の警告発行**:
   - `(symbol? var)` で `type-env` に型束縛が見つからない場合：
     - `(emit-untyped-boundary-warning var (or boundary-kind 'task))` を呼び出し。
     - 従来通り安全側の `'deep-copy` を返却（後方互換性と CWE-362 安全性を完全維持）。
   - シグネチャ後方互換性:
     - `(classify-capture-mode var . opt-args)`（第2引数: `opt-env`、第3引数: `opt-boundary-kind`）として既存呼び出しコードを一切壊さない。

### Step 3: `with-channel` および `spawn-task` での境界コンテキスト連携
1. `%split-spawn-task` において、自由変数のキャプチャ判定時に `boundary-kind = 'spawn-task` を伝播。
2. `%split-with-channel` において、自由変数のキャプチャ判定時に `boundary-kind = 'with-channel` を伝播。

### Step 4: 単体テストの拡充 (`tests/concurrency/test_pass_split_planes.scm`)
1. **型なし変数の警告発行テスト**:
   - `(reset-untyped-boundary-warnings!)` 実行後、型注釈のない変数 `untyped-buf` を `spawn-task` または `classify-capture-mode` でキャプチャさせた際、`untyped-boundary-warnings` に登録されることを検証。
2. **明示的アノテーションによる警告抑制テスト**:
   - `(: untyped-buf deep-copy)` や `(: untyped-buf any)` を指定した場合、戻り値が `'deep-copy` であり、かつ警告リストに追加されないことを検証。
3. **型付き変数の偽陽性ゼロテスト**:
   - `channel`, `integer`, `fixnum`, `boolean` 等の型注釈がある変数では警告リストが空のままであることを検証。
4. **一括抑制フラグのテスト**:
   - `(set-car! *warn-untyped-boundary* #f)` 設定時に警告が出力・記録されないことを検証。

---

## 6. 完了条件 / Success Criteria (DoD)

- [x] **静的警告の出力**:
  - 型注釈がなく型推論できない変数がタスク/チャネル境界をまたぐ際、`[WARN] pass-synapse-split-planes: Untyped variable ...` が標準エラー出力に明瞭に表示されること。
- [x] **安全性の維持**:
  - 警告出力後も既存の Shared-Nothing 安全性仕様どおり `'deep-copy` が適用され、ランタイム挙動が壊れないこと。
- [x] **警告抑制の手段**:
  - 明示的型注釈 `(: var deep-copy)` または `(: var any)` により、意図的なディープコピーを警告なしで指定できること。
  - `*warn-untyped-boundary*` または環境変数 `ULISP_WARN_UNTYPED_BOUNDARY=0` によりコンパイラ警告を一括抑制できること。
- [x] **偽陽性ゼロ (Zero False Positives)**:
  - 正しく型付けされた並行処理コード（`channel`, `spsc-channel`, `integer`, `boolean` 等）において警告が一切発生しないこと。
- [x] **テスト 100% PASS**:
  - `make -C ulisp test_pass_split_planes` が 100% PASS すること。
  - `make -C ulisp test_pass_check_affine` が 100% PASS すること。
  - `make -C ulisp test` 全件が 100% PASS すること。
  - リポジトリ品質ゲート (`make format`, `make static_analysis`, `make test`) がエラー 0 件・カバレッジ 80% 以上で PASS すること。



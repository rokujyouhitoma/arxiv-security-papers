---
ID: 641
種別: Feature
優先度: High
ステータス: Closed (Completed)
---

# [FEAT] ホスト・カーネル境界サニタイザおよびディープコピー機構の実装 (ID: 641)

## 1. 概要 / Summary

[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 4 Task 4.1 に基づき、コントロールプレーン（Layer 1: R7RS）とアフィン部分言語コア（Layer 2: ASC 計算プレーン）の間でデータを受け渡す際の **ホスト・カーネル境界サニタイザ (`boundary.scm`)** を Pure Scheme で実装する。

従来の共有ヒープ型並行モデルでは、異なるスレッド間でオブジェクトの参照（ポインタ）を不用意に共有した結果、競合状態（Data Race）、不正な同時変更、および片方のタスク終了に伴う解放後メモリ参照（Use-After-Free / CWE-416）が頻発していた。
本 Issue では、ホスト・カーネル分離型アーキテクチャの根幹原則である **Shared-Nothing メモリモデル** を物理的・構造的に強制する境界防壁を確立する。

コントロールプレーンからタスクへ、あるいはタスクからコントロールプレーンへデータを転送する際、即値型（Fixnum, Flonum, Boolean, Character, Nil）はゼロコピーでレジスタ渡しを行い、複合型（Pair / リスト、Vector、String、Bytevector）は転送先のエフェメラルアリーナ（`<task-arena>`）またはホストヒープへ再帰的ディープコピーを行う。さらに、循環参照の検出（スタック枯渇 CWE-674 防御）およびポインタ非共有性の監査検証機能を備え、プレーン間のメモリ汚染を根絶する。

---

## 2. ガバナンス・専門エージェント多角レビュー / Governance & Reviews

本 Issue は、リポジトリ統治規約（[`.agents/AGENTS.md`](../../../.agents/AGENTS.md)）に従い、PM 主導のもと全 16 専門エージェントによる多角的設計レビューを統合して策定された。

- **Project Manager (PM) (Chair / Governance)**:
  - Phase 4（ホスト・カーネル境界 ＆ 世代管理型投機タスク破棄）の最優先マイルストーン（Task 4.1）として、Task 4.2（世代管理型投機タスク破棄 #642）および Phase 5（10 万並行ベンチマーク #643）の安全基盤となる。Pure Scheme で実装し、外部 C ライブラリ依存ゼロおよび全件テスト合格（DoD）を厳格に管理する。
- **IT Specialist (Programming Languages & Compilers / PLC)**:
  - 即値型判定（`immediate-value?`）をインライン述語として高速化し、複合型の再帰コピーにおいて `task-arena` のバンプアロケータ（`arena-allocate!`）を直接駆動する。
  - AOT コンパイラ生成コードおよびランタイム双方から呼び出し可能な純粋手続きとして設計し、`bin/ulisp-boot` ネイティブコンパイル環境での完全動作を保証する。
- **Systems Architect (SA)**:
  - DSN-37 第 8.1 節および第 9.1 節に基づき、Layer 1（R7RS GC ヒープ空間）と Layer 2（ASC プロセスローカル・エフェメラルアリーナ空間）の間に厳格な物理的境界線を敷く。境界を越えるポインタの直通（Raw Pointer Bleed）を 1 ビットも許容しない Shared-Nothing ガードを確立する。
- **Information Security Specialist (SEC)**:
  - ポインタエイリアシング破壊（CWE-825）、解放後使用（CWE-416）、および循環参照による無限再帰・スタックオーバーフロー DoS（CWE-674）に対する防御機構を設計に組み込む。
  - 探索深度制限（`*boundary-max-depth*`）および訪問済みオブジェクト検出（Visited-Set）により、細工された循環データ構造の流入を安全に遮断する。また、セキュリティ監査述語 `(shared-pointer? a b)` を提供し、ポインタ完全非共有を保証する。
- **Software Quality Assurance Specialist (SQA)**:
  - 単体テストスイート `tests/concurrency/test_boundary.scm` において、即値型のゼロコピー同一性、リスト・木構造・ベクタ・文字列・バイトベクタの再帰ディープコピー検証、コピー先での破壊的変更が呼び出し元に波及しないことの独立性検証、循環リスト検知ガード、および `shared-pointer?` によるポインタ完全非共有検証を自動テスト化する。
- **Software Development (SWD)**:
  - ランタイム本体 `ulisp/runtime/concurrency/boundary.scm`、ライブラリ定義 `ulisp/lib/ulisp/concurrency/boundary.sld`、テスト `tests/concurrency/test_boundary.scm` を作成し、`ulisp/Makefile` に `test_boundary` を統合する。
- **Database Specialist (DB)** / **Network Specialist (NET)** / **IT Specialist (NLP & IR)**:
  - 外部ネットワークパケットや DB クエリ結果セットをタスクプールへ投入する際のステージングバッファとして、ディープコピー処理のメモリ局所性（Cache Locality）とアリーナバンプ加算の効率性を確認。
- **IT Service Manager (SM)** / **Systems Auditor (AU)**:
  - 境界通過時の総コピーバイト数（`boundary-copied-bytes`）の追跡機構を備え、DSN-37 第 9.1 節で警告されている境界コピーオーバーヘッドの可観測性（Observability）を担保する。

---

## 3. 脅威分析とセキュリティ要件 / Threat Modeling & Security Requirements

| 脅威分類 (STRIDE) | 脆弱性タイプ (CWE) | 潜在リスク・攻撃シナリオ | 防護策・緩和設計 (Mitigation) |
| :--- | :--- | :--- | :--- |
| **Tampering / Memory Corruption** | CWE-825 (Expired Pointer Dereference) / CWE-416 (Use-After-Free) | R7RS 側のオブジェクトポインタがサニタイズされずにタスクアリーナへ持ち込まれ、タスク終了後のアリーナ一括破棄（$O(1)$ リセット）または外側 GC によって無効化され、解放後メモリ破壊を引き起こす。 | 複合型オブジェクトを相手側アリーナまたはヒープへ完全に再帰ディープコピーし、元のポインタ参照を一切残さない（Shared-Nothing）。 |
| **Denial of Service** | CWE-674 (Uncontrolled Recursion) | 悪意ある入力や不注意により循環参照を持つリスト（`set-cdr!` 等で自己参照した構造）が境界サニタイザに渡され、再帰コピー処理が無限ループしてスタックを枯渇（スタックオーバーフロー）させる。 | 再帰コピー時に訪問済みオブジェクト（Visited Pair / Vector）を追跡し、循環を検知した時点で決定論的にエラー（CWE-674 ガード）を送出する。また、最大再帰深度上限（`*boundary-max-depth*`）を強制する。 |
| **Denial of Service** | CWE-400 (Uncontrolled Resource Consumption) | ギガバイト級の超巨大オブジェクトグラフをタスク境界へ投入し、タスクの極小アリーナ（2KB〜8KB）を瞬時に超過させて過剰なチャンク確保を引き起こす。 | 最大サニタイズバイト数上限（`*boundary-max-bytes*`）を設け、制限超過時は早期に例外を送出してアリーナ枯渇とリソース独占を抑止する。 |
| **Information Disclosure / Elevation of Privilege** | CWE-200 / CWE-284 | 並列タスクが書き換えた中間バッファが、ポインタ共有によりコントロールプレーン側の認証情報やグローバル変数を意図せず上書きする。 | コピー前後のオブジェクト間でアドレス重複が 1 点も存在しないことを `shared-pointer?` 述語で検証可能にし、プレーン分離の気密性を保証する。 |

---

## 4. トレーサビリティ / Traceability

- **正典設計仕様書**:
  - [DSN-37: ホスト・カーネル分離型 階層 CSP/アクター・ハイブリッド並行処理基盤 ＆ AOT コンパイルパイプライン包括的アーキテクチャ設計書](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md)
    - 第 8.1 節: 境界におけるデータサニタイズ（Shared-Nothing）
    - 第 9.1 節: ① 境界サニタイズ（ディープコピー）の激しいオーバーヘッドと局所適用
    - 第 10 章: プレーン別の責務境界とハイブリッド運用の原則
    - 第 14.6 節: Phase 4 ホスト・カーネル境界 ＆ 世代管理型投機タスク破棄 (Task 4.1)
  - [DSN-36: Zero-libc Pure Scheme ベアメタルランタイム包括設計仕様書](../../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
  - [DSN-33: uLisp x86-64 ネイティブ AOT コンパイラ包括設計仕様書](../../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- **関連・先行 Issue**:
  - [Issue 630: プロセスローカル・エフェメラルアリーナおよび O(1) 瞬時全破棄機構の実装](../closed/630-implement-synapse-task-independent-bump-arena.md)
  - [Issue 633: 線形所有権移譲チャネルおよび有界バックプレッシャー機構の実装](../closed/633-implement-synapse-first-class-p2p-channel.md)
  - [Issue 637: ホスト・カーネル分離パス (split-planes-pass) および動的パス注入機構](../closed/637-implement-nanopass-split-planes-pass.md)
  - [Issue 638: アフィン線形所有権静的検査パス (check-affine-types) および自動 RAII Drop の実装](../closed/638-implement-nanopass-check-affine-types-and-raii-drop.md)
  - [Issue 639: FBIP (Perceus) インプレース再利用最適化パスの実装](../closed/639-implement-nanopass-fbip-inplace-optimization.md)
  - [Issue 640: Nanopass ループバックエッジ・プロローグ セーフポイント判定自動注入パスの実装](../closed/640-implement-nanopass-inject-fuel-checks-pass.md)

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

### 新規作成
- `ulisp/runtime/concurrency/boundary.scm`: 境界サニタイザおよびディープコピー機構本体
  - 即値型高速判定 `immediate-value?`
  - アリーナへのディープコピー `sanitize-to-arena`
  - ホストヒープへのディープコピー `sanitize-from-arena`
  - 循環参照検出およびスタックオーバーフロー保護（CWE-674 ガード）
  - ポインタ共有監査述語 `shared-pointer?`
  - 境界コピー統計カウンタ（`boundary-stats`）
- `ulisp/lib/ulisp/concurrency/boundary.sld`: R7RS ライブラリ定義
  - `(ulisp concurrency boundary)`
- `tests/concurrency/test_boundary.scm`: 単体・統合テストスイート
  - 即値型パス、リスト・ベクタ・文字列・バイトベクタディープコピー、破壊的変更耐性、循環参照検知、`shared-pointer?` 検証

### 既存更新
- `ulisp/Makefile`:
  - `test_boundary` ターゲット追加
  - `lint_sexpr` への新規ファイル追加
  - `test` ターゲットへの統合
- `docs/issues/README.md`: Issue #641 ステータス管理

---

## 6. 実装方針 / Implementation Plan

Target Branch: `feat/641-synapse-boundary-sanitizer`

### Step 1: 即値型述語および基本定数の定義 (`boundary.scm`)
1. **境界定数**:
   - `*boundary-max-depth*`: `1024` (最大再帰深度上限: CWE-674 防御)
   - `*boundary-max-bytes*`: `1048576` (単一サニタイズ最大容量: 1MB CWE-400 防御)
2. **型判定述語**:
   - `(immediate-value? x)`: `(or (number? x) (boolean? x) (char? x) (null? x) (symbol? x))`
     ※ Symbol も不変アトムとしてゼロコピー扱い可能。

### Step 2: 循環参照検出機構（Cycle Detector）の実装
1. **訪問済み追跡（Visited-Set）**:
   - 再帰コピー中に走査した複合オブジェクト（Pair, Vector）の識別アドレスまたは同一性（`memq`）を追跡。
   - 既に走査中のオブジェクトが再度現れた場合、`error "sanitize: circular reference detected (CWE-674)"` を送出。
2. **深度カウンタ**:
   - 再帰ステップごとに `depth` をインクリメントし、`*boundary-max-depth*` 超過時にエラー。

### Step 3: アリーナ転送ディープコピー (`sanitize-to-arena`)
1. **引数**: `(sanitize-to-arena val arena)`
2. **ディスパッチロジック**:
   - `(immediate-value? val)` $\implies$ そのまま返却（レジスタ渡し、完全ゼロコピー）。
   - `(pair? val)` $\implies$ 要素を再帰コピーし、`arena` から新しい Pair を確保して構築。
   - `(vector? val)` $\implies$ 各要素を再帰コピーし、`arena` から連続領域を確保して構築。
   - `(string? val)` $\implies$ 文字列のコピー（`string-copy` 相当）を作成。
   - `(bytevector? val)` $\implies$ バイト列のコピー（`bytevector-copy` 相当）を作成。

### Step 4: ホスト転送ディープコピー (`sanitize-from-arena`)
1. **引数**: `(sanitize-from-arena val)`
2. **ディスパッチロジック**:
   - タスクアリーナ内で生成された結果オブジェクトを、ホスト（コントロールプレーン）側の標準 GC ヒープへディープコピー。
   - これにより、タスク終了後にアリーナが $O(1)$ 瞬時リセットされても、ホスト側に安全に結果が残存する。

### Step 5: セキュリティ監査述語 (`shared-pointer?`) の実装
1. **ポインタ共有検出**:
   - 2つのオブジェクトグラフ $A$ と $B$ を走査し、共通の Pair / Vector / String / Bytevector ポインタ（`eq?`）が存在するかを判定。
   - サニタイズ後、`(shared-pointer? original copied)` が確実に `#f` を返すことを検証。

### Step 6: テストスイートの作成と Makefile 統合
1. `tests/concurrency/test_boundary.scm` を作成し、全 6 グループのテストケースを実装。
2. `ulisp/Makefile` に `test_boundary` を統合し、全件テストおよび `lint_sexpr` を実行。

---

## 7. 完了条件 / Success Criteria (DoD)

### 定量的検証項目
1. **即値型の完全ゼロコピー**:
   - Fixnum, Flonum, Bool, Char, Symbol, Nil がオーバーヘッドゼロ（レジスタ直接渡し）で同一値を保つこと。
2. **複合型の再帰的ディープコピー**:
   - ネストしたリスト、ベクタ、文字列、バイトベクタがすべて完全に複製されること。
3. **完全なポインタ非共有 (Shared-Nothing)**:
   - `(shared-pointer? original sanitized)` が `#f` を返し、元データへの破壊的変更がサニタイズ先へ一切波及しないこと。
4. **循環参照の安全な遮断**:
   - 循環リストおよび循環ベクタが入力された際、無限ループにならず確実に CWE-674 エラーで拒絶されること。
5. **全テストハーネスの合格**:
   - `make -C ulisp test_boundary`: 全テストケース PASS。
   - `make -C ulisp lint_sexpr`: 全ファイル S 式括弧整合性 PASS。
   - 相対パスリンク 100% 準拠（絶対パス 0 件）。

---

## 8. 検証結果 / Verification Results

### 8.1 単体・統合テスト結果 (`test_boundary`)
`tests/concurrency/test_boundary.scm` を AOT ネイティブバイナリとしてビルド・実行し、全 6 グループ 33 アサーションが 100% PASS することを実証した。

```text
=======================================================
 Starting Synapse Boundary Sanitizer Tests (#641)
=======================================================

--- Group 1: Immediate Value Pass-Through (Zero-Copy) ---
PASS: 1.1 fixnum is immediate-value?
PASS: 1.2 boolean is immediate-value?
PASS: 1.3 char is immediate-value?
PASS: 1.4 null is immediate-value?
PASS: 1.5 symbol is immediate-value?
PASS: 1.6 pair is not immediate-value?
PASS: 1.7 vector is not immediate-value?
PASS: 1.8 fixnum passed without arena bump
PASS: 1.9 arena offset unchanged for immediate

--- Group 2: List / Pair Deep Copy & Pointer Non-Sharing ---
PASS: 2.1 list structure preserved
PASS: 2.2 top-level pair pointer is distinct
PASS: 2.3 shared-pointer? detects zero shared pair pointers
PASS: 2.4 arena offset advanced by pair allocations
PASS: 2.5 nested tree preserved
PASS: 2.6 tree pointers completely distinct
PASS: 2.7 modifying kernel list leaves host list unaffected
PASS: 2.8 kernel list modified in isolation

--- Group 3: Vector Deep Copy & Isolation ---
PASS: 3.1 vector structure preserved
PASS: 3.2 vector identity distinct
PASS: 3.3 inner vector identity distinct
PASS: 3.4 shared-pointer? is false for vector graph
PASS: 3.5 host vector intact after copied vector modification

--- Group 4: String & Bytevector Deep Copy ---
PASS: 4.1 string content preserved
PASS: 4.2 string pointer is distinct
PASS: 4.3 shared-pointer? is false for distinct string
PASS: 4.4 bytevector content preserved
PASS: 4.5 bytevector pointer is distinct
PASS: 4.6 shared-pointer? is false for distinct bytevector

--- Group 5: Circular Reference Detection (CWE-674 Guard) ---
PASS: 5.1 circular list is safely rejected (CWE-674)
PASS: 5.2 circular vector is safely rejected (CWE-674)

--- Group 6: Kernel to Host Transfer (sanitize-from-arena) ---
PASS: 6.1 result replicated into host format
PASS: 6.2 host data shares no pointers with kernel data
PASS: 6.3 host data remains fully accessible after task arena reset
=======================================================
 Boundary Sanitizer Test Summary: 33 passed, 0 failed.
=======================================================
```

### 8.2 Synapse 並行性ランタイム ＆ Nanopass パイプライン包括回帰検証
既存の全並行性ランタイムおよびコンパイラパス群との一括回帰テストを実行し、リグレッションゼロを確認。

```text
make -C ulisp test_arena test_atomic test_queue test_channel test_boundary test_context_switch test_scheduler test_preemption test_pass_split_planes test_pass_check_affine test_pass_fbip test_pass_inject_safepoints
==> ALL TEST SUITES PASSED (0 failures across all 680+ assertions).
```

### 8.3 括弧整合性・構文静的解析 (`lint_sexpr`)
`make -C ulisp lint_sexpr`: 111 ファイル全て括弧バランス PASS。

---

## 9. 結論 / Conclusion

[DSN-37](../../designs/DSN-37-synapse_dual_plane_concurrent_runtime_architecture.md) Phase 4 Task 4.1 に規定されたホスト・カーネル境界サニタイザおよびディープコピー機構の実装が完了した。
これにより、Layer 1（R7RS GC 管理ヒープ）と Layer 2（ASC プロセスローカル・エフェメラルアリーナ）間におけるポインタ流出（Raw Pointer Bleed）および Use-After-Free（CWE-416）が物理的・構造的に根絶され、循環参照 DoS（CWE-674）に対する堅牢な防壁が確立された。
本成果をもって Issue #641 をクローズし、続く Phase 4 Task 4.2（世代管理型投機タスク破棄機構 #642）の実装へと進む。

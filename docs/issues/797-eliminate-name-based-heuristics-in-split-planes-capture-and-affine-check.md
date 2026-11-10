---
ID: 797
種別: Bug
優先度: Medium
ステータス: Open (In Progress)
---

# [BUG/TYPE] split-planes パスおよび ASC カーネルにおける変数名依存ヒューリスティックの完全撤廃 (ID: 797)

## 1. 概要 / Summary
Issue #792 において Affine 検査のローカル束縛推論から変数名ヒントが廃止されたが、依然としてコンパイラパイプライン内の以下の2箇所で変数名プレフィックスに基づくアドホックなヒューリスティックが残存している：

1. `ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm:195` の `classify-capture-mode`：
   - 境界（`spawn-task`, `with-channel`）において「所有権移動 (`'linear-move`)」「即値 (`'immediate`)」「ディープコピー (`'deep-copy`)」のいずれを適用するかを変数名（`chan*`, `rx*`, `tx*`, `n*`, `i*`, `count*` 等）でハードコード判定している。
   - このため、型注釈のないチャネル（例: 1文字変数 `c` や `pipe`）は誤ってディープコピーされ、逆に `channel-count` や `chan-val` という名前の通常の値（数値や文字列等）が線形移動として扱われてしまう重大な型混同（CWE-843）が存在する。
2. `ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm:344` の `kernel-formal-linear?`：
   - ASC カーネル（`%asc-kernel`）の引数検査において、型注釈のない素のシンボル引数 `(symbol? f)` に対し、フォールバックとして `(linear-variable-name-hint? f)` を呼び出している。

本 Issue では、これら残存する名前依存判定を完全に撤廃し、型環境・型注釈（`(: var type)`）、コンストラクタ式、および境界構文（`with-channel`）が導出する厳密な型シグネチャに基づく健全かつ安全な判定機構へ置き換える。

### 再現手順 / Steps to Reproduce
1. チャネル変数として `c` という名前の変数を用意し、タスク境界（`spawn-task` または `with-channel`）を跨いで渡す。
2. `classify-capture-mode` が名前プレフィックスに一致しないため、所有権移動（`linear-move`）ではなくディープコピー（`deep-copy`）を選択してしまう挙動を確認する。
3. また、`chan-val` という名前の通常整数値（即値）が線形移動扱いとなり、後続処理で不正な移動検出や型混同を引き起こす現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- Target Files:
  - `ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm`
  - `ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm`
  - `tests/concurrency/test_pass_split_planes.scm`
  - `tests/concurrency/test_pass_check_affine.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm)
  - `classify-capture-mode`: 名前プレフィックス検査（`%str-starts-with?` 等）を完全撤廃し、型環境 `type-env` / 型注釈に基づく分類へ移行。
  - `%split-with-channel`: `with-channel` で生成されるエンドポイント（`rx`, `tx`）に型注釈 `(: rx channel)` を自動付与して `%asc-kernel` に渡す。
  - `%split-spawn-task`: 外側の型束縛環境を追跡し、キャプチャされた自由変数の型情報を伝播。
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
  - `kernel-formal-linear?`: `(symbol? f)` の名前ヒントフォールバックを撤廃し、明示的型注釈 `(: var type)` / `(var : type)` のみで線形判定。
  - `linear-variable-name-hint?`: 名前プレフィックス依存ロジックを排斥。
- [ ] [tests/concurrency/test_pass_split_planes.scm](../../tests/concurrency/test_pass_split_planes.scm)
  - Group 2 を型注釈・型環境ベースの分類テストに全面改修。
  - 任意名 `c` のチャネルが `linear-move` となり、`chan-val` 整数が `deep-copy` / `immediate` となるテストを追加。
- [ ] [tests/concurrency/test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm)
  - Group 1 および Group 9 を更新し、名前ヒントなしでの厳格な型注釈駆動線形性検証を強化。

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- 型注釈構文（Issue #749）やシグネチャ伝播（Issue #792）の導入以前のプロトタイプ段階で、「チャネルは通常 `chan`, `rx`, `tx` という名前で定義される」「即値カウンタは `n`, `i`, `count` という名前で定義される」というヒューリスティックに依存した実装がなされていた。
- Issue #792 ではローカル束縛（`let` 式）における名前依存を撤廃したが、プレーン分割パス（`pass_split_planes.scm`）のキャプチャ分類およびカーネル引数（`kernel-formal-linear?`）のフォールバックが未改修のまま残存していた。

---

## 4. 脅威モデリングと安全性検証 / Threat Modeling & Safety Analysis
- **CWE-843 (Type Confusion)**:
  - 変数名に依存した型判定は、攻撃者が意図的に `chan_payload` や `rx_flag` と命名した通常オブジェクトを境界越境させ、ランタイムにチャネル用アンラップや所有権移動を誤認させる脆弱性を生む。静的型注釈・コンストラクタ判定への一元化により型混同を完全防止する。
- **CWE-362 (Race Condition) / CWE-662 (Improper Synchronization)**:
  - 任意名（`c`, `pipe`）の線形チャネルがディープコピーされた場合、2つのタスクが同一の基底リソースに対して非同期に競合アクセスし、ロックフリーリングのメモリコヒーレンシ破壊に至る。厳格な線形移動により排他所有権を保証する。
- **CWE-416 (Use-After-Free)**:
  - 境界越境時に所有権が移動したリソースの元タスクでの参照を静的に検出し、確実にコンパイル時エラーまたは RAII ドロップへ誘導する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/797-eliminate-name-based-heuristics-in-split-planes-and-affine`

### 1. `pass_split_planes.scm` の型駆動化
- `(classify-capture-mode var type-env)` へのシグネチャ拡張（第2引数オプショナルで後方互換性を保持）。
- `var` の型または束縛式を `type-env` から検索：
  - `linear-type?`（`channel`, `spsc-channel`, `bounded-channel`, `linear`）$\to$ `'linear-move`
  - `immediate-type?`（`fixnum`, `integer`, `boolean`, `char`, `number` 等）またはリテラル定数 $\to$ `'immediate`
  - それ以外（未知の型、型注釈なし複合オブジェクト） $\to$ デフォルトで安全な `'deep-copy`（Shared-Nothing 安全性）。
- 変数名プレフィックス・サフィックス判定（`%str-starts-with?` 等）を完全削除。
- `with-channel` において、生成される `rx-sym`, `tx-sym` に `(: rx-sym channel)` の型注釈を付与して `%asc-kernel` を生成。
- `split-planes-ast` において、外側の `let` や `define` の型注釈を環境 `type-env` として再帰走査に引き渡す。

### 2. `pass_check_affine.scm` のカーネル引数厳格化
- `kernel-formal-linear?` において、`(symbol? f)` のフォールバックで `linear-variable-name-hint?` を呼ぶロジックを廃止し、明示的型注釈（`(: var type)` / `(var : type)` / `(var type)`）がない素のシンボルは非線形（`#f`）と判定。
- `linear-variable-name-hint?` の使用箇所を廃止。

### 3. テストスイートの更新・拡充
- `test_pass_split_planes.scm`:
  - 任意名 `c`（型注釈 `channel` あり）が `'linear-move` に分類されること。
  - `chan-val`（型注釈 `integer` または数値束縛）が `'immediate` または `'deep-copy` に分類されること。
  - 型注釈なし変数がデフォルトで安全な `'deep-copy` に分類されること。
- `test_pass_check_affine.scm`:
  - `kernel-formal-linear?` が名前プレフィックスに依存せず、型注釈 `(: c channel)` で正しく線形と判定されること。
  - 素のシンボル `rx`, `tx` で型注釈がない場合は非線形として扱われ、`(: rx channel)` で線形と判定されること。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] `pass_split_planes.scm` および `pass_check_affine.scm` から変数名プレフィックス/サフィックス判定関数（`%str-starts-with? "chan"`, `linear-variable-name-hint?` 等）が完全撤廃されていること。
- [ ] 任意名（`c`, `pipe` 等）のチャネル変数が型注釈または `with-channel` 経由で正しく `'linear-move` に分類されること。
- [ ] `make -C ulisp test_pass_split_planes` が 100% PASS すること。
- [ ] `make -C ulisp test_pass_check_affine` が 100% PASS すること。
- [ ] `make -C ulisp test_preemption` および `make -C ulisp bench_concurrency_gate` が 100% PASS すること。
- [ ] 相対パス規約が 100% 遵守されていること（絶対パス 0 件）。



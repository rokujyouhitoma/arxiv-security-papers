---
ID: 749
種別: Bug
優先度: High
ステータス: Closed
関連 Issue: #736, #638, #719, #740
---

# [BUG/SEC] 変数名依存を廃止した型・束縛解析に基づく厳格な Affine 線形性検査 (ID: 749)

## 1. 概要 / Summary

Synapse 並行性ランタイム向けコンパイラ最適化・検証パス `pass_check_affine.scm`（`pass-synapse-check-affine`）において、線形リソース（Channel 等）の判定処理 `linear-variable?` が依然として変数名シンボルの文字列プレフィックス・サフィックス（`chan*`, `rx*`, `tx*`, `res*`, `buf*`, `*-channel` 等）に依存している。

この結果、以下の2つの深刻なセキュリティおよび品質上の不具合が存在する：
1. **False Negative (見逃し / CWE-416, CWE-775)**: 開発者が一般的な変数名（`c`, `conn`, `pipe`, `stream` 等）を命名した場合、線形リソースとみなされず二重送信（Use-After-Move）やクローズ後送信、あるいは関数終了時の未消費リーク（Missing RAII Drop）が完全にすり抜ける。
2. **False Positive (誤検知 / CWE-843)**: 通常の非線形変数（例: `result`, `buffer-size`, `resource-id` 等）がプレフィックス規約に偶然一致した場合、線形変数と誤認され、複数回参照による Use-After-Move 誤検知エラーや、不要な `%affine-drop!` の不正注入によるランタイム異常が発生する。

本 Issue では、変数名の静的文字列マッチング依存を完全撤廃し、**生成式（コンストラクタ）の型推論（Provenance Type Inference）** および **線形環境テーブル（`lin-env`）による動的スコープ追跡** に基づく正統な Affine 型・線形性検証パスを確立する。

---

## 2. 脅威モデル分析とセキュリティ影響 (STRIDE & CWE)

| 脅威分類 (STRIDE) | 対象 CWE | 影響度 | 脅威シナリオと脆弱性のメカニズム |
| :--- | :--- | :---: | :--- |
| **Tampering (改ざん)** / **Elevation of Privilege** | **CWE-416**: Use After Free / Use After Move | High | 変数名がプレフィックスに一致しないチャネル（例: `c`）において、`channel-send!` や別関数への所有権移動後に再度 `channel-send!` を実行してもコンパイルエラーとならず、二重送信やデータ破壊（競合送信）が発生する。 |
| **Denial of Service (サービス拒否)** | **CWE-775**: Missing Release of Resource after Effective Lifetime | High | 関数内で生成されたチャネルが消費されずにスコープを抜ける際、変数名が非規約であると自動 RAII drop (`%affine-drop!`) が注入されず、チャネル資源やバッファがリークして OOM やデッドロックに至る。 |
| **Integrity Violation (整合性侵害)** | **CWE-843**: Access of Resource Using Incompatible Type | Medium | 通常の整数や文字列変数（例: `(let ((result 42)) ...)`）が "res" プレフィックスにより線形リソースと誤認され、関数末尾で `(%affine-drop! result)` が注入されて不正な構造体アクセスやメモリ破壊を引き起こす。 |

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

### なぜこの問題が存在しているか
1. **初期プロトタイプの実装残存 (`pass_check_affine.scm` L52-65)**:
   ```scheme
   (define (linear-variable? sym)
     (if (not (symbol? sym))
         #f
         (let ((s (symbol->string sym)))
           (or (%str-starts-with? "chan" s)
               (%str-starts-with? "rx" s)
               (%str-starts-with? "tx" s)
               (%str-starts-with? "res" s)
               (%str-starts-with? "buf" s) ...))))
   ```
   初期の DSN-37 構想段階で簡易モックとして作成された変数名プレフィックス判定が、そのまま製品コードおよび検証ロジックに残存していた。
2. **`let` 束縛時の右辺値（RHS）型の無視 (`pass_check_affine.scm` L212-216, L380-388)**:
   `let` 式の走査において、右辺式 `val-expr` のコンストラクタ式（`make-channel`, `make-spsc-channel` 等）を解析せず、左辺の変数名 `v` のみで `(linear-variable? v)` を呼び出して `lin-env` に登録している。
3. **消費・移動判定での二重変数名チェック (`pass_check_affine.scm` L267, L287, L307 等)**:
   引数 `arg` が消費されたかどうかの判定において、`lin-env` に存在するかどうかではなく `(and (symbol? arg) (linear-variable? arg))` と変数名で再度ガードしているため、`lin-env` に登録された非プレフィックス変数が消費状態（`'moved`）に遷移しない。

---

## 4. 恒久対策アーキテクチャ設計 (Type-Based Affine Verification)

### 4.1 生成式プロベナンス解析 (`linear-constructor-expr?` / `infer-linear-type`)
右辺式（RHS）を再帰的に解析し、線形リソースを生成または所有権を返却する式を厳密に特定する：
- **明示的コンストラクタ**:
  - `make-channel`, `make-spsc-channel`, `make-bounded-channel`, `make-channel-internal`
  - `make-channel-pair`, `channel-pair`
- **既存の線形変数からの所有権移転**:
  - `(let ((c2 c1)) ...)` において、`c1` が現在の `lin-env` で線形リソース（`'available`）である場合、`c2` も線形リソースとして継承され、`c1` は `'moved` に遷移する。
- **型アノテーション付き式**:
  - `(!linear expr)`, `(: var Channel)` 等の構文メタデータ。

### 4.2 環境駆動型リニア変数判定 (`lin-variable?` / `lin-env-is-linear?`)
- あるシンボルが線形変数であるかの判定を、**「現在の `lin-env` にエントリが存在するか否か (`lin-env-lookup`)」** のみに一本化する。
- 変数名が `c`, `pipe`, `stream` であっても、線形コンストラクタから束縛された時点で `lin-env` に `available` として登録され、完全な線形性保証の対象となる。
- 通常変数 `result` や `buffer-size` は `lin-env` に登録されないため、二重参照も合法となり、不要な `%affine-drop!` も一切注入されない。

### 4.3 カーネル仮引数（Formals）の型注釈と後方互換ヒント
- `%asc-kernel` の formals において：
  - 型アノテーション `(c : channel)` または `(: c channel)` を第1級サポート。
  - 既存のテストケースとの後方互換性維持のため、未注釈引数に限り `linear-variable-name-hint?`（旧 `linear-variable?`）をフォールバックとして許容。

---

## 5. 影響範囲と関連ファイル / Scope and Affected Files

- [x] [`ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm`](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm):
  - `linear-constructor-expr?` / `infer-linear-type` の追加
  - `linear-variable?` の名称を `linear-variable-name-hint?` へ後退させ、コアロジックを環境駆動型へ刷新
  - `validate-affine-ast-internal` の `let` / 引数走査における型推論・所有権移動の刷新
  - `transform-affine-expr` の `let` における SPSC 昇格および RAII drop 注入の型駆動化
  - `%asc-kernel` formals の型注釈パース対応
- [x] [`ulisp/lib/ulisp/concurrency/passes/check_affine.sld`](../../ulisp/lib/ulisp/concurrency/passes/check_affine.sld):
  - 新規 API（`linear-constructor-expr?` 等）のエクスポート追加
- [x] [`tests/concurrency/test_pass_check_affine.scm`](../../tests/concurrency/test_pass_check_affine.scm):
  - Group 1 のテスト維持＋任意変数名（`c`, `pipe`, `my-conn`）の Use-After-Move 検出テスト追加
  - 非線形プレフィックス変数（`result`, `buffer-size`）の合法利用・drop 非注入テスト追加
  - Formals 型アノテーション（`(: c channel)`）のテスト追加

---

## 6. 実装方針 / Implementation Plan

Target Branch: `fix/749-implement-type-based-affine-linearity-check`

### Step 1: 線形コンストラクタ判定と型推論関数の実装
`pass_check_affine.scm` に以下の述語群を実装：
```scheme
(define (linear-constructor-op? op)
  (memq op '(make-channel make-spsc-channel make-bounded-channel
             make-channel-internal make-channel-pair channel-pair)))

(define (linear-constructor-expr? expr env)
  (cond
    ((not (pair? expr))
     (if (symbol? expr)
         ;; Variable reference: transfers ownership if expr is an available linear variable in env
         (eq? (lin-env-lookup env expr) 'available)
         #f))
    ((linear-constructor-op? (car expr)) #t)
    ((and (eq? (car expr) '!linear) (pair? (cdr expr))) #t)
    (else #f)))
```

### Step 2: `validate-affine-ast-internal` の刷新
1. `let` 束縛走査:
   - 右辺式 `val-expr` を検証。
   - `(linear-constructor-expr? val-expr cur-env)` が真、または（後方互換）`linear-variable-name-hint?` が真の場合にのみ `v` を `lin-env-add-available`。
   - 右辺式が既存の線形変数 `u` の場合、`u` を `cur-env` 上で `'moved` にマーク（所有権転送）。
2. アプリケーション・消費操作:
   - `channel-send!`, `channel-consume!`, 一般関数呼び出しにおいて、`arg` が線形かどうかの判定を `(and (symbol? arg) (lin-env-lookup cur-env arg))` に置換。

### Step 3: `transform-affine-expr` の刷新
1. `let` 束縛時の SPSC 最適化昇格（`make-channel` -> `make-spsc-channel`）:
   - 変数名に依存せず、型が線形チャネルである場合に適用。
2. RAII drop 注入:
   - `lin-env` に実際に登録された変数のみを `drops` 対象とし、通常変数 `result` 等には絶対に `%affine-drop!` を注入しない。

### Step 4: ユニットテストの拡充と検証
`tests/concurrency/test_pass_check_affine.scm` に以下を追加：
- Case 1: `(let ((c (make-channel 1))) (channel-send! c 10) (channel-send! c 20))` -> 二重送信 Use-After-Move 検出
- Case 2: `(let ((pipe (make-channel 1))) (forward pipe) (channel-send! pipe 10))` -> 所有権移転後の Use-After-Move 検出
- Case 3: `(let ((result 100)) (+ result result))` -> "res" プレフィックスでも非線形変数として正常通過、drop 注入なし
- Case 4: `(let ((buffer-size 1024)) (+ buffer-size 1))` -> "buf" プレフィックスでも非線形変数として正常通過
- Case 5: `(let ((c1 (make-channel 1))) (let ((c2 c1)) (channel-send! c1 10)))` -> 変数リネーム後の旧変数使用を Use-After-Move として検出

### Step 5: 全体品質ゲートの実行
- `make -C ulisp test_pass_check_affine` PASS
- `make -C ulisp test_pass_fbip` PASS
- `make -C ulisp test` PASS
- `make verify_quality` PASS

---

## 7. 完了条件 / Success Criteria (DoD)

- [x] **型・プロベナンス解析の導入**: `linear-constructor-expr?` が実装され、`make-channel` 等の式または既存線形変数のリネームから線形性が正しく導出されること
- [x] **環境駆動型判定への完全移行**: `let` 内部および引数消費（`channel-send!`, `channel-close!` 等）において、変数名プレフィックスではなく `lin-env` 登録状態に基づいて線形性が判定されること
- [x] **False Negative の解消**: 任意の変数名（`c`, `conn`, `pipe`, `stream` 等）であっても、線形リソースの二重消費・Use-After-Move が 100% 確実にコンパイル時検出されること
- [x] **False Positive の解消**: 非線形変数（`result`, `buffer-size` 等）が変数名によって線形扱いされず、多重参照が合法となり、不要な `%affine-drop!` が注入されないこと
- [x] **テストスイートの拡充と完全合格**:
  - `tests/concurrency/test_pass_check_affine.scm` に新規テストが追加され、全グループが PASS すること
  - `make -C ulisp test_pass_check_affine`、`make -C ulisp test_pass_fbip` が PASS すること
  - `make -C ulisp test`（Nanopass 38パス、セルフホスティング bit-for-bit）が 100% PASS すること
- [x] **全体品質ゲートの完全通過**: `make verify_quality`（全2766+テスト、型チェック、静的解析）が 100% PASS すること

---
ID: 736
種別: Bug
優先度: Medium
ステータス: Closed
---

# [BUG/SEC] チャネル複数回受信を可能にする Affine 検査の借用/移動分離および 4 つの Nanopass パスの不具合修正 (ID: 736)

## 1. 概要 / Summary
現在、`pass_check_affine.scm` では関数引数に渡された線形変数（`rx`, `tx`, `chan` 等）を無条件に `'moved` にするため、同じチャネルから2回 `channel-recv!` / `channel-send!` を行うだけで `use-after-move` エラーになる問題がある（項目 B8）。あわせて、Synapse の 4 つの Nanopass パス（`pass_split_planes`, `pass_check_affine`, `pass_fbip`, `pass_inject_safepoints`）に存在する既知の不具合を修正する。

### 再現手順 / Steps to Reproduce
1. `%asc-kernel` 内で `(begin (channel-recv! rx) (channel-recv! rx))` をコンパイルする。
2. 1回目の `(channel-recv! rx)` で `rx` が `'moved` になり、2回目の受信で `[AFFINE-LINEARITY-VIOLATION] Use-After-Move` エラーが発生する。
3. また、`pass_fbip.scm` でペア以外の drop 対象変数が `cons` の再利用先に使われる問題や、`pass_inject_safepoints.scm` で複数式ボディの4要素目以降が切り捨てられる問題などが発生する。

### 再現環境 / Environment
- OS / Env: Linux (x86-64 / AArch64 / Portable C99)
- File: `ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm`, `pass_check_affine.scm`, `pass_fbip.scm`, `pass_inject_safepoints.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm)
- [x] [pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)
- [x] [pass_fbip.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_fbip.scm)
- [x] [pass_inject_safepoints.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_inject_safepoints.scm)
- [x] [test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- `pass_check_affine.scm` が「チャネルエンドポイント自体を別タスクへ Move / close する場合」と「チャネルを使って送受信（Borrow）する場合」を区別せず、すべての呼び出し引数を `'moved` に遷移させていたため。
- 4つのパスにおいて Named-let 構文の未処理、`pass_fbip` での型未確認の再利用と `if` 分岐 drop 集合マージ漏れ、`pass_inject_safepoints` での `(caddr kernel-node)` 単一式決め打ちが存在するため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: チャネル変数名を `linear-variable?` にマッチしない名前に変えて検査を回避する。
* **恒久対策 (Permanent Fix)**: チャネルに対する送受信操作ではチャネル変数を借用（`'available` 維持）として扱い、送信ペイロードや `channel-close!` / 別タスクへの転送時のみ `'moved` にするとともに、4つのパスの AST 処理バグをすべて修正する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/736-fix-affine-checker-and-four-passes`

1. `pass_check_affine.scm`: `channel-recv!` / `channel-send!` 等のチャネル引数は借用（`'available` 維持）とし、複数回の送受信を許可する（送信される線形データや `channel-close!` は `'moved` にする）。Named-let にも対応させる。
2. `pass_split_planes.scm`: Named-let の自由変数抽出バグおよびキャプチャ分類の不整合を修正する。
3. `pass_fbip.scm`: ペア型であることが保証された変数のみを `%fbip-reuse-pair!` 対象にし、`if` 分岐の drop 集合マージを修正する。
4. `pass_inject_safepoints.scm`: `%asc-kernel` のボディが複数式（`(cddr kernel-node)`）の場合に後続式を切り捨てないよう修正する。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 同一チャネルからの2回以上の `channel-recv!` / `channel-send!` が Affine 検査を通過し、Use-After-Move（閉じた後の使用や送信済みデータの再利用）は正しく拒否されること。
- [x] 4つのパスすべての既知の不具合が解消され、回帰テストが追加されていること。
- [x] `make format`, `make static_analysis`, `make test` がすべて PASS すること。


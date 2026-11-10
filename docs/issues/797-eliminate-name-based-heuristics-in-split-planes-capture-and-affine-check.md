---
ID: 797
種別: Bug
優先度: Medium
ステータス: Open (New)
---

# [BUG/TYPE] split-planes パスおよび ASC カーネルにおける変数名依存ヒューリスティックの完全撤廃 (ID: 797)

## 1. 概要 / Summary
Issue #792 において Affine 検査の束縛推論から変数名ヒントが廃止されたが、依然として以下の2箇所で変数名プレフィックスに基づくアドホックなヒューリスティックが残存している：
1. `oas_split_planes.scm:198` の `classify-capture-mode`：境界において「所有権の移動 (move)」と「ディープコピー (deep-copy)」のいずれを適用するかを変数名で判定している。このため、型注釈のないチャネル（例: `c`）は誤ってディープコピーされ、逆に `chan` で始まる名前の通常の値（数値や文字列等）が所有権移動として扱われてしまう。
2. `oas_check_affine.scm:356` の ASC カーネル引数判定：型注釈のないシンボル引数を名前（`rx`, `tx`, `chan` 等）で linear か否か判定している。
本 Issue では、これら残存する名前依存判定を完全に撤廃し、型注釈・修飾子・関数シグネチャに基づく健全かつ安全な判定機構へ置き換える。

### 再現手順 / Steps to Reproduce
1. チャネル変数として `c` という名前の変数を用意し、タスク境界を跨いで渡す。
2. `classify-capture-mode` が名前で弾き、所有権移動ではなくディープコピーを選択してしまう挙動を確認する。
3. また、`chan-val` という名前の通常整数値が移動扱いとなり、後続でアクセス不能になる現象を確認する。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- File: [pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm), [pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm)

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm) - `classify-capture-mode`
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_check_affine.scm) - ASC 引数検査
- [ ] [tests/concurrency/test_pass_split_planes.scm](../../tests/concurrency/test_pass_split_planes.scm) - 単体テスト
- [ ] [tests/concurrency/test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm) - 単体テスト

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
- 型注釈や型伝播の未整備なプロトタイプ段階で導入された「名前の先頭プレフィックスでチャネルや線形資源を判別する」という暫定実装が、パスの一部に残存していたため。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**:
  - 変数名に必ず `chan` / `rx` / `tx` の命名規則を厳守する。
* **恒久対策 (Permanent Fix)**:
  - `classify-capture-mode` を型検査器（Type Checker）と連携させ、変数の静的型情報（linear / affine / normal）に基づいて capture mode を決定する。
  - 型注釈のないシンボル引数に対しては型推論を適用するか、型注釈を必須化し、名前ベースの推測を行った場合はコンパイル時警告またはエラーを送出する。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/797-eliminate-name-based-heuristics-in-split-planes-and-affine`

1. `pass_split_planes.scm` の `classify-capture-mode` を型シグネチャ・注釈駆動に改修。
2. `pass_check_affine.scm` の引数検査から名前ヒントを排斥し、型定義に基づく厳密な linear 検査を適用。
3. `c` などの任意の変数名を持つチャネルが正しく所有権移動され、通常の変数がディープコピーされる単体テストを追加。

---

## 6. 完了条件 / Success Criteria (DoD)
- [ ] 変数名による型・キャプチャモード判定ロジックがコードベースから 0 件になること。
- [ ] 型注釈なしチャネルや非標準命名変数を用いた境界移動が意図通り動作すること。
- [ ] 既存の Affine 検査テストおよび新規追加テストが 100% PASS すること。


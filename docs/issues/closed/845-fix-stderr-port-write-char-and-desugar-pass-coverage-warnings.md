---
ID: 845
種別: Bug
優先度: High
ステータス: Closed
---

# [BUG] 標準エラー出力文字出力バッファ破壊およびNanopass脱糖カバレッジ警告の解消 (ID: 845)

## 1. 概要 / Summary
`make -C ulisp build/ulisp-modular` および `make -C ulisp test` 実行時において、以下の3つの重要障害・警告ノイズが発生していた：
1. **標準エラー出力文字欠落・改行欠落バグ**:
   `missing desugar rules for eliminated forms: definequasiquote...whenunlessas --64...` のように、空白文字・括弧・改行文字が欠落して 1 行に密着・連結して出力される。
2. **脱糖ルール未充足警告 (Spurious / Missing Desugar Coverage Warnings)**:
   - Pass 026〜029 の個別サブパスにおいて `[WARN] define-pass desugar-XXX: missing desugar rules for eliminated forms: ...` が大量出力される。
   - Pass 030 (`desugar-all`) においても `quasiquote`, `when`, `unless` が未充足として警告される。
   - テストスイート実行時に、祖先言語（`L_cst`）で削除された `define-library` や `import` 等が `desugar-all` の削除タグに誤混入し警告される。
3. **テストスイート表示の空行ノイズおよび境界警告ノイズ**:
   - `=== [Test Suite: Synapse Reduction Safepoint Injection] ===` 等において各グループヘッダの間に空行が連続して出力され、端末表示が過剰に肥大化する。
   - `pass-synapse-split-planes` の境界横断警告 (`[WARN] pass-synapse-split-planes: Untyped variable...`) がテスト実行時に stderr へ直接印字されノイズとなる。

本 Issue では、stderr 単一文字出力バッファの堅牢化、Nanopass 脱糖カバレッジ検証ロジックの適正化、全脱糖構文の 100% 網羅、およびテストランナー表示の整流化を行い、完全無警告・整流化ビルドを実現する。

### 再現手順 / Steps to Reproduce
1. `make -C ulisp build/ulisp-modular` を実行。
2. `=== Compiling Frontend Passes Module ===` のフェーズで `[WARN]` 出力が発生し、改行されずに `as --64...` と同一行に連結される。
3. `make -C ulisp test` を実行すると、グループヘッダ間に連続した空行および `[WARN] pass-synapse-split-planes` が出力される。

### 再現環境 / Environment
- OS / Env: Linux x86_64 (Self-hosting native seed binary `bin/ulisp-boot`)
- File: `ulisp/lib/port.scm`, `ulisp/compiler/nanopass.scm`, `ulisp/frontend/026_desugar_constructors.scm` 等

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/port.scm](../../ulisp/lib/port.scm)
- [ ] [ulisp/compiler/nanopass.scm](../../ulisp/compiler/nanopass.scm)
- [ ] [ulisp/compiler/nanopass_meta.scm](../../ulisp/compiler/nanopass_meta.scm)
- [ ] [ulisp/frontend/026_desugar_constructors.scm](../../ulisp/frontend/026_desugar_constructors.scm)
- [ ] [ulisp/frontend/027_desugar_conditionals.scm](../../ulisp/frontend/027_desugar_conditionals.scm)
- [ ] [ulisp/frontend/028_desugar_bindings.scm](../../ulisp/frontend/028_desugar_bindings.scm)
- [ ] [ulisp/frontend/029_desugar_dynamic.scm](../../ulisp/frontend/029_desugar_dynamic.scm)
- [ ] [ulisp/frontend/030_desugar.scm](../../ulisp/frontend/030_desugar.scm)
- [ ] [ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm](../../ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm)
- [ ] [ulisp/tests/passes/common.scm](../../ulisp/tests/passes/common.scm)
- [ ] [tests/concurrency/test_pass_inject_safepoints.scm](../../tests/concurrency/test_pass_inject_safepoints.scm)
- [ ] [tests/concurrency/test_pass_check_affine.scm](../../tests/concurrency/test_pass_check_affine.scm)
- [ ] [tests/concurrency/test_pass_fbip.scm](../../tests/concurrency/test_pass_fbip.scm)
- [ ] [tests/concurrency/test_pass_split_planes.scm](../../tests/concurrency/test_pass_split_planes.scm)
- [ ] [ulisp/tests/test_scope.scm](../../ulisp/tests/test_scope.scm)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis
1. **`port-write-char` バッファ複製による NUL 文字出力**:
   - `lib/port.scm` の `port-write-char` は、fd 2 (stderr) への出力時に `(let ((buf (cons 0 (cons 0 '())))) (%raw-store! ...) (sys-write 2 (%ptr-untag buf) 1))` を行っていた。
   - コンパイラの最適化パス（CP0 / let 変数展開）が `buf` の割り当て式を複数箇所にインライン展開したため、文字を格納したセルとは別の「初期値 0 のままの新規 cons セル」が `sys-write` に渡され、端末上で不可視の NUL 文字 (`\0`) が出力されていた。
2. **サブパス言語シグネチャの不整合**:
   - Pass 026〜029（コンストラクタ、条件分岐、束縛、動的環境）は特定構文のみを脱糖するサブパス（出力は依然 `L_src` 準拠）であるにもかかわらず、型シグネチャが `L_src -> L_core` と宣言されていた。
   - `nanopass-verify-fusion-coverage` は `L_core` で削除される全 18 構文が単一サブパス内でカバーされていないと判定し、不正な警告を発出していた。
3. **`quasiquote`, `when`, `unless` の Picopass 未登録**:
   - `L_core` は `quasiquote`, `when`, `unless` を削除構文として定義しているが、Pass 030 (`desugar-all`) に対応する Picopass ルールが存在しなかったため、真の未充足構文として警告されていた。
4. **祖先言語削除タグの誤混入**:
   - `compiler/nanopass_meta.scm` の `nanopass-get-language-removed-tags` が、`(nanopass-combine-sets diff-heads direct-removed)` により、`L_src` 生成時に既に削除済みの `define-library` や `import` などのタグまで `L_core` の `parent-removed` 経由で結合してしまい、誤警告の原因となっていた。
   - 正しくは、入力言語 `l-in` と出力言語 `l-out` の直接の差分 `(language-diff l-in l-out)` の `diff-heads` のみを検証対象とすべきである。
5. **テストヘッダの過剰空行および境界警告**:
   - `test_pass_inject_safepoints.scm` 等において `(newline)` と `(display "--- Group... ---\n")` が無条件に呼ばれ、テスト成功時（非詳細モード）に空行とグループ名だけが連続して印字されていた。
   - `pass_split_planes.scm` において、境界横断解析の記録と stderr への警告印字が同一フラグで制御されていたため、テスト実行時に警告が直接出力されていた。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix
* **暫定対処 (Workaround)**: なし（警告を無視してビルドを継続することは可能だが、ログが汚損しエラー特定が困難になる）。
* **恒久対策 (Permanent Fix)**:
  1. `lib/port.scm` に静的文字列バッファ `*port-stderr-buf*` (長さ 1 の string) を導入し、`sys-write-stderr` 経由で確実に 1 バイトを出力。
  2. `compiler/nanopass.scm` の警告フォーマッタを単一文字列 (`string-append`) かつ明示的 `\n` 終端に統一。
  3. Pass 026〜029 を `: L_src (ir) -> L_src ()` に修正。
  4. `rule-desugar-quasiquote` および `rule-desugar-when-unless` を実装し、Pass 030 (`desugar-all`) に統合。
  5. `nanopass-get-language-removed-tags` で `diff-heads` のみを返却し、祖先言語削除タグを排除。
  6. `pass_split_planes.scm` の stderr 警告印字フラグ `*warn-untyped-boundary-print*` を分離（デフォルト `#f`）。
  7. `tests/passes/common.scm` に `print-group` を新設し、非詳細モード時の過剰空行を完全抑止。

---

## 5. 実装方針 / Implementation Plan
Target Branch: `fix/845-fix-stderr-port-write-char-and-desugar-pass-coverage-warnings`

1. **`ulisp/lib/port.scm`**:
   - `*port-stderr-buf*` を定義（`make-string 1`）。
   - `port-write-char` の stderr 分岐を `(string-set! *port-stderr-buf* 0 ch) (sys-write-stderr *port-stderr-buf*)` に置換。
2. **`ulisp/compiler/nanopass.scm`**:
   - `missing` リストの文字列フォーマット関数を導入し、`string-append` で `[WARN] ...\n` の 1 行を組み立てて `display` する。
3. **`ulisp/compiler/nanopass_meta.scm`**:
   - `nanopass-get-language-removed-tags` を `diff-heads` のみを返す実装に単純化・適正化。
4. **`ulisp/frontend/026_desugar_constructors.scm`**:
   - `desugar-quasiquote-datum`, `desugar-quasiquote`, `rule-desugar-quasiquote` を実装。
   - シグネチャを `: L_src (ir) -> L_src ()` に変更。
5. **`ulisp/frontend/027_desugar_conditionals.scm`**:
   - `desugar-when`, `desugar-unless`, `rule-desugar-when-unless` を実装。
   - シグネチャを `: L_src (ir) -> L_src ()` に変更。
6. **`ulisp/frontend/028_desugar_bindings.scm` & `029_desugar_dynamic.scm`**:
   - 出力言語を `L_src` に変更。
7. **`ulisp/frontend/030_desugar.scm`**:
   - `rule-desugar-quasiquote` と `rule-desugar-when-unless` を `fuse-rules` に追加。
8. **`ulisp/lib/ulisp/concurrency/passes/pass_split_planes.scm`**:
   - `*warn-untyped-boundary-print*` を導入し、テスト中の stderr 警告出力を抑制。
9. **`ulisp/tests/passes/common.scm` & テストスクリプト群**:
   - `print-group` ヘルパーを定義し、各テストスイート内の空行および無駄なグループヘッダ出力を抑制。

10. **`ulisp/backend/160_backend_c.scm`**:
    - `scan-c-blocks!` において `%block` だけでなく `%label` もローカルブロックとして走査・記録するように拡張。C バックエンド生成コードにおける局所ループラベルへのジャンプが関数呼び出しではなく `goto` 文として正しく出力されるように修正（`test_gc_stress` のリンクエラー解消）。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] S式括弧チェック (`python3 scripts/lint_sexpr.py`) が 53 ファイルすべてで PASS（バランス保証）すること。
- [x] `make -C ulisp build/ulisp-modular` が `[WARN]` 0件、エラー0件でビルド完了し、静的リンクされた実行可能バイナリが生成されること。
- [x] `make -C ulisp bootstrap` がネイティブシードで直接起動し、Stage 2/Stage 3 の bit-for-bit 固定点一致をパスすること。
- [x] `make -C ulisp test` の全テストスイートが `[WARN]` 0件、空行ノイズなしで 100% PASS すること。

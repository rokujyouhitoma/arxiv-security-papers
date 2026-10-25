---
ID: 611
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] R7RS (scheme process-context) 環境変数取得手続き (get-environment-variable / get-environment-variables) の実装 (ID: 611)

## 1. 概要 / Summary
R7RS-small §6.14 および `(scheme process-context)` で規定されている環境変数取得手続きを実装する。
1. `(get-environment-variable name)`: 指定した名前の環境変数の値を文字列として取得（存在しない場合は `#f` を返却）
2. `(get-environment-variables)`: プロセスに設定されている全環境変数を名前と値のペア `("NAME" . "VALUE")` の連想リストとして返却

POSIX 低レベルレイヤーまたはネイティブランタイムにおいて `environ` ポインタ配列を走査するメカニズムを確立し、完全なスタンドアロン実行系として環境情報を Scheme 空間に露出させる。

---

## 2. トレーサビリティ / Traceability
- R7RS-small:
  - §6.14: System interface (`get-environment-variable`, `get-environment-variables`)
  - §5.6 / §5.1: `(scheme process-context)`
- 関連仕様書:
  - [R7RS 仕様準拠状況リファレンス](../../ulisp/docs/ref_r7rs_compliance.md) §1.3 (6.14), §1.4 (`(scheme process-context)`)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/lib/posix.scm](../../ulisp/lib/posix.scm): POSIX `environ` 外部シンボル参照または走査プリミティブの実装
- [ ] [ulisp/compiler/primitives.scm](../../ulisp/compiler/primitives.scm) または [ulisp/runtime.c](../../ulisp/runtime.c): ランタイム初期化時の `environ` ポインタ保持
- [ ] [ulisp/lib/scheme/process-context.sld](../../ulisp/lib/scheme/process-context.sld): 手続き定義およびエクスポート
- [ ] [ulisp/tests/test_process_context.scm](../../ulisp/tests/test_process_context.scm): 環境変数取得テスト
- [ ] [ulisp/docs/ref_r7rs_compliance.md](../../ulisp/docs/ref_r7rs_compliance.md): 準拠ステータス更新 (50% → 100%)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/611-implement-r7rs-process-context-environment-variables`

1. POSIX C ランタイムまたは x86-64 エントリポイントから渡される `char **environ` を Scheme 空間から安全に参照できるようにする。
2. `get-environment-variable`: 与えられた文字列キーを `KEY=` 形式で `environ` 配列内を線形探索し、該当する環境変数の値を Scheme 文字列として割り当てて返却する。一致しない場合は `#f` を返す。
3. `get-environment-variables`: `environ` の各 `KEY=VALUE` 文字列を走査し、`=` の位置で分割して `(cons "KEY" "VALUE")` の連想リストを構築して返却する。
4. `(scheme process-context)` SLD からエクスポートし、既存の `exit`, `emergency-exit`, `command-line` と合わせて仕様適合率 100% を達成する。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `(get-environment-variable "PATH")` 等の既存環境変数が文字列で取得できること。
- [ ] 存在しない環境変数に対して `(get-environment-variable "NON_EXISTENT_VAR")` が `#f` を返すこと。
- [ ] `(get-environment-variables)` が `(("KEY" . "VAL") ...)` のペアのリストを返すこと。
- [ ] `(import (scheme process-context))` から利用可能であること。
- [ ] `ref_r7rs_compliance.md` の `(scheme process-context)` ステータスが 100% に更新されること。

---
ID: 391
種別: Feature
優先度: Medium
ステータス: Open (New)
---

# [FEAT/ENH] pylisp.condition 現場復帰・非巻き戻し型コンディション機構の実装 (ID: 391)

## 1. 概要 / Summary
Common Lispのコンディションシステムに倣い、スタックフレームを巻き戻さずに例外現場の中間状態を維持したまま上位ハンドラに修復戦略（Restart）を問い合わせ、現場へ復帰して計算を継続する非巻き戻し型エラー処理基盤を実装する。

従来の `try-except` によるスタックアンワインド（ローカル変数やネットワーク接続の中間状態喪失）を排し、現場コードが `val = signal(...)` で修復結果を受け取る現場継続型プロトコルを義務付ける。さらに、上位ハンドラが利用可能な修復戦略を動的に内省する `compute_restarts()` API、および `asyncio` タスク越境時にコンテキストを安全伝播する `safe_create_task` を提供する。

---

## 2. トレーサビリティ / Traceability
- 関連資料: [DSN-29 Python-LISP 統合アーキテクチャ設計仕様書 第4章・第8.3節・第9章](../designs/DSN-29-python_lisp_integrated_architecture_specification.md#4-pylispcondition-現場復帰非巻き戻し型コンディション機構-条件付き自作採用)
- 関連仕様: Common Lisp Condition System (ANSI Common Lisp / Kent Pitman), Python `contextvars` / `asyncio`

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [src/pylisp/__init__.py](../../src/pylisp/__init__.py)
- [ ] [src/pylisp/condition.py](../../src/pylisp/condition.py)
- [ ] [tests/pylisp/test_condition.py](../../tests/pylisp/test_condition.py)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/391-implement-pylisp-condition-restarts-mechanism`

1. **コアクラス・構造の実装**:
   - `Restart`: `__slots__ = ("name", "callback", "description", "takes_arg")` を定義し、シグナル現場で提供される修復戦略をカプセル化。
   - `Condition(Exception)`: すべてのシグナル可能なコンディションの基底クラス。
   - `ConditionController`: `compute_restarts() -> list[Restart]` および `invoke_restart(name, *args, **kwargs)` を提供。
   - `ConditionContext`: ハンドラマップを保持し、階層的スコープをサポート。
2. **コンテキスト・シグナル関数の実装**:
   - `handler_bind`: 修復ポリシー（`dict[type[Condition], Callable[[ConditionController], None]]`）を登録するコンテキストマネージャ。
   - `signal(condition, restarts) -> Any`:
     - 現在の `ConditionContext` を探索し、一致するハンドラを実行。
     - ハンドラがリスタートを選択した場合はスタックを巻き戻さず、コールバックの戻り値を現場へ直接返却。
     - ハンドラ不在時またはリスタート未選択時は、通常の例外として `raise condition` し、スタック解体へフォールバック。
   - `safe_create_task(coro)`: `contextvars.copy_context()` を確実に引き継いで非同期タスクを生成（Python 3.11+ / 3.10 両対応）。
3. **テストスイートの整備**:
   - 現場復帰テスト（シグナル地点以降のローカルコードが正常に完遂することの確認）。
   - `compute_restarts()` によるリスタート一覧内省テスト。
   - ハンドラ不在時の標準例外送出テスト。
   - `safe_create_task` を経由した非同期コルーチン境界越えコンディション伝播テスト。
   - `mypy --strict` 型適合性検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] `src/pylisp/condition.py` に `Condition`, `Restart`, `ConditionController`, `handler_bind`, `signal`, `safe_create_task` が実装され、`mypy --strict` に完全合格すること。
- [ ] スタックアンワインドを行わず、現場で `val = signal(...)` の戻り値を受け取って後続処理を継続できること。
- [ ] 上位ハンドラから `compute_restarts()` により利用可能なリスタートを内省・選択できること。
- [ ] ハンドラ未設定時は通常の例外としてスタック解体されること。
- [ ] 非同期タスク境界を越えてコンディションハンドラが正しく伝播すること。
- [ ] `tests/pylisp/test_condition.py` の全テストが通過すること。

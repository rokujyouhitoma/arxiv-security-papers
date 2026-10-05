---
ID: 483
種別: Feature
優先度: High
ステータス: Closed
---

# [FEAT] ALisp Phase 2: Object-Capability (with-caps)・Managed Virtual Port・状態ロールバック基盤の実装 (ID: 483)

## 1. 概要 / Summary
[DSN-32 第12.3節](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) に基づき、ALisp のサンドボックス実行基盤（Phase 2）を実装する。
大域環境からの破壊的 I/O プリミティブの不可視化、明示的な能力トークン（`with-caps`）による最小権限実行、権限の減衰原則（Attenuation）、物理 I/O を捕捉する `ManagedPort`（Byte Budget クォータおよびインメモリ隔離ループバック）、Fuel 枯渇時の自動スナップショット・トランザクションロールバック、および Taint Tracking の基礎を構築する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-32: AILISP (ALisp + ILisp) 次世代AIコーディングエージェント実行環境包括的アーキテクチャ設計書](../../docs/designs/DSN-32-ailisp_agent_lisp_architecture_specification.md) (第 3.2 節, 第 3.3 節, 第 4 章, 第 7 章, 第 12.3 節)
  - [DSN-07: Security Guard & RBAC](../../docs/designs/DSN-07-security_guard_and_rbac.md)
- **対象サブシステム**:
  - `alisp/caps/`
  - `alisp/metering.py` (スナップショット・ロールバック統合)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [alisp/caps/__init__.py](../../alisp/caps/__init__.py) (`Capability` 基底クラス, Attenuation ロジック, `with-caps` マクロ)
- [x] [alisp/caps/fs.py](../../alisp/caps/fs.py) (`FileSystemCapability`, パスプレフィックスホワイトリスト)
- [x] [alisp/caps/net.py](../../alisp/caps/net.py) (`NetworkCapability`, ホスト/メソッド制限)
- [x] [alisp/caps/port.py](../../alisp/caps/port.py) (`ManagedPort`, Byte Budget, インメモリ `bytevector-port` ループバック隔離)
- [x] [alisp/caps/taint.py](../../alisp/caps/taint.py) (`TaintedValue` ラッパー, `untaint` プリミティブ, Sink 遮断)
- [x] [alisp/metering.py](../../alisp/metering.py) (環境フレーム Cell および Port バッファの世代ロールバック)
- [x] [tests/alisp/test_phase2_caps_and_sandbox.py](../../tests/alisp/test_phase2_caps_and_sandbox.py) (単体・統合テスト)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/483-implement-alisp-phase2-ocaps-and-managed-port`

1. **Object-Capability 基盤 (`alisp/caps/`)**:
   - `Capability` 基盤を実装。親 Capability からより狭いスコープの子 Capability を生成する `attenuate` メソッドを規定。
   - `FileSystemCapability` (`fs-cap`) による特定ディレクトリ外アクセスの遮断。
   - `NetworkCapability` (`net-cap`) による許可ドメイン外通信の遮断。
2. **`ManagedPort` の実装 (`alisp/caps/port.py`)**:
   - ILisp のポートシステムをラップし、最大転送バイト数（Byte Budget: デフォルト 1MB）を制限。
   - 認可されていないパスへの書き込み要求を安全にメモリ内バッファ（`bytevector-port`）へリダイレクト。
3. **トランザクションロールバックの実装**:
   - `with-fuel` 突入時に変更可能 Cell の世代番号および Managed Port 書き込みログを記録。
   - `FuelExhaustedException` 発生時に直前の状態へアトミックに戻すロールバック処理を実行。
4. **Taint Tracking 基礎 (`alisp/caps/taint.py`)**:
   - 外部ソース由来データへの `tainted` タグ付与と、未認可 Sink 渡しのブロック。

---

## 5. 完了条件 / Success Criteria (DoD)
- [x] `fs-cap` を持たないコードから `open-output-file` の呼び出しが 100% 遮断されること。
- [x] 認可パス外へのファイル書き込みがメモリ内バッファへ隔離され、実ファイルシステムが一切変更されないこと。
- [x] `with-fuel` 内で状態変更（`set!`）を行った後に意図的に Fuel 枯渇を起こした場合、すべての変数が実行前状態へ巻き戻ること。
- [x] `make format`, `make static_analysis`, `make test` が 100% PASS すること。

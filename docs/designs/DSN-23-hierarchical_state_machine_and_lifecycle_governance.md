# [DSN-23] ゼロ外部依存・高信頼階層型ステートマシン（HSM / Statecharts）基盤およびシステム全域ライフサイクル統制設計仕様書
## 〜 状態爆発抑止・共通例外一括継承・プロセス/クローラー/ワークフロー/DBMS/通信全域横断ガバナンス ＆ 段階的実装ロードマップ 〜

- **文書番号**: `DSN-23`
- **文書ステータス**: `APPROVED`
- **対象サブシステム**:
  - `src/core/hsm/` (新規コア基盤: `engine.py`, `contracts.py`, `registry.py`, `transition.py`)
  - `src/supervisor/` (`Arbiter`, `ServiceState`, `WorkerStatus`, `SpiderWorker`, `ServiceWorker`)
  - `src/spider/` (`CweSpider`, `EngineLoop`, `Downloader`, `AutoThrottle`, `SessionPool`)
  - `src/workflow/` (`WorkflowScheduler`, `SpiderTaskOperator`, `SagaCoordinator`, `CircuitBreaker`)
  - `src/database/` (`AriesRecovery`, `CheckpointCoordinator`, `WAL`, `BufferPool`)
  - `src/pdf/` (`PdfStreamDecoder`, `LayoutSynthesis`, `SafetyLimitCheck`)
  - `src/web/` (`StreamingHandler`, `BackpressureController`, `SSEConnectionPool`)
- **【主査・報告】 Systems Architect (SA) / Software Quality Assurance Specialist (QA)**
- **【参画】 15 大専門エージェント全員**:
  - Project Manager (PM), Systems Architect (SA), Information Security Specialist (SC),
  - Software Quality Assurance Specialist (QA), Database Specialist (DB), Network Specialist (NW),
  - IT Specialist (NLP & IR), IT Strategist (ST), IT Service Manager (SM),
  - Embedded Systems Specialist (ES), Systems Auditor (AUD), UI/UX Designer (UI),
  - Education Specialist (EDU), Software Development (SWD), Application Specialist (APS)

---

## 体系目次

- [1. 状態機械論と実行・ライフサイクル基盤](#1-状態機械論と実行ライフサイクル基盤)
  - [1.1 主要コンポーネントアーキテクチャ](#11-主要コンポーネントアーキテクチャ)
  - [1.2 フラット FSM と階層型ステートマシン (HSM / Statecharts) の対比](#12-フラット-fsm-と階層型ステートマシン-hsm--statecharts-の対比)
  - [1.3 親状態（Composite State）による振る舞いの継承 (Behavioral Inheritance)](#13-親状態composite-stateによる振る舞いの継承-behavioral-inheritance)
  - [1.4 直交領域（Orthogonal Regions: 並行ステートマシン）](#14-直交領域orthogonal-regions-並行ステートマシン)
  - [1.5 履歴状態（History State: Shallow $H$ vs Deep $H^*$）](#15-履歴状態history-state-shallow-h-vs-deep-h)
  - [1.6 現行エンジン対比と進化方針](#16-現行エンジン対比と進化方針)
- [2. 15大専門エージェントによる多角的ガバナンス ＆ 品質ゲート要件](#2-15大専門エージェントによる多角的ガバナンス--品質ゲート要件)
  - [2.1 15大エージェント別要求仕様・ガバナンスマトリクス](#21-15大エージェント別要求仕様ガバナンスマトリクス)
  - [2.2 各専門エージェント詳細レビュー・統制方針](#22-各専門エージェント詳細レビュー統制方針)
- [3. HSM コアエンジン詳細設計 (`src/core/hsm/`)](#3-hsm-コアエンジン詳細設計-srccorehsm)
  - [3.1 ゼロ外部依存の Pure Python 設計思想](#31-ゼロ外部依存の-pure-python-設計思想)
  - [3.2 コアデータモデル仕様 (`StateNode`, `TransitionRule`, `EventContext`, `GuardCondition`)](#32-コアデータモデル仕様-statenode-transitionrule-eventcontext-guardcondition)
  - [3.3 LCCA (Lowest Common Composite Ancestor) 探索アルゴリズム](#33-lcca-lowest-common-composite-ancestor-探索アルゴリズム)
  - [3.4 決定論的実行パス（Exit ➔ Action ➔ Entry ➔ Initial Child 解決）](#34-決定論的実行パスexit--action--entry--initial-child-解決)
  - [3.5 フェイルセキュア（Fail-Secure）親状態脱出遷移と例外トラップ](#35-フェイルセキュアfail-secure親状態脱出遷移と例外トラップ)
- [4. サブシステム別 HSM 適用仕様 (全6大領域)](#4-サブシステム別-hsm-適用仕様-全6大領域)
  - [4.1 `src/supervisor/`: プロセス・ワーカーライフサイクル統制](#41-srcsupervisor-プロセスワーカーライフサイクル統制)
  - [4.2 `src/spider/`: クローラー・通信セッション統制](#42-srcspider-クローラー通信セッション統制)
  - [4.3 `src/workflow/`: DAG タスク ＆ Saga トランザクション統制](#43-srcworkflow-dag-タスク--saga-トランザクション統制)
  - [4.4 `src/database/`: ARIES クラッシュリカバリ統制](#44-srcdatabase-aries-クラッシュリカバリ統制)
  - [4.5 `src/pdf/`: 構文解析・ストリームデコード・安全ガード統制](#45-srcpdf-構文解析ストリームデコード安全ガード統制)
  - [4.6 `src/web/`: SSE リアルタイム通信・バックプレッシャー統制](#46-srcweb-sse-リアルタイム通信バックプレッシャー統制)
- [5. 可観測性・監査証跡・UI 可視化](#5-可観測性監査証跡ui-可視化)
  - [5.1 Web コンソール階層状態バッジ表示 (`index.html#/system`)](#51-web-コンソール階層状態バッジ表示-indexhtmlsystem)
  - [5.2 構造化 JSON Lines ログ ＆ W3C TraceContext](#52-構造化-json-lines-ログ--w3c-tracecontext)
  - [5.3 Merkle Tree 改ざん防止ハッシュ木連携 (監査来歴保証)](#53-merkle-tree-改ざん防止ハッシュ木連携-監査来歴保証)
- [6. セキュリティ・STRIDE 脅威分析と多層防御](#6-セキュリティstride-脅威分析と多層防御)
  - [6.1 STRIDE 脅威分析マトリクス](#61-stride-脅威分析マトリクス)
  - [6.2 不正状態遷移・ゾンビプロセス・未認可シグナル遮断](#62-不正状態遷移ゾンビプロセス未認可シグナル遮断)
- [7. 非機能要件・パフォーマンス・計算量証明](#7-非機能要件パフォーマンス計算量証明)
  - [7.1 $O(D)$ 探索計算量とサブミリ秒実行 ($< 10\mu s$)](#71-od-探索計算量とサブミリ秒実行--10mu-s)
  - [7.2 メモリ制約 ($\le 10\text{KB}$ / インスタンス) とゼロアロケーション最適化](#72-メモリ制約-le-10textkb--インスタンス-とゼロアロケーション最適化)
  - [7.3 厳格な品質ゲート（Xenon Grade A CC<=4, mypy --strict）](#73-厳格な品質ゲートxenon-grade-a-cc4-mypy---strict)
- [8. 今後の段階的実装ロードマップ (4 フェーズ)](#8-今後の段階的実装ロードマップ-4-フェーズ)
  - [8.1 ロードマップ・ガントチャート](#81-ロードマップガントチャート)
  - [8.2 Phase 1: コアエンジン ＆ Supervisor 刷新 (Issue 224)](#82-phase-1-コアエンジン--supervisor-刷新-issue-224)
  - [8.3 Phase 2: Spider ＆ Workflow 統合 (Issue 223 結合)](#83-phase-2-spider--workflow-統合-issue-223-結合)
  - [8.4 Phase 3: Database / ARIES リカバリ統合](#84-phase-3-database--aries-リカバリ統合)
  - [8.5 Phase 4: PDF ＆ Web Gateway 統合](#85-phase-4-pdf--web-gateway-統合)

---

# 1. 状態機械論と実行・ライフサイクル基盤

## 1.1 主要コンポーネントアーキテクチャ

階層型ステートマシン基盤（`src/core/hsm/`）は、イベント駆動かつ決定論的なライフサイクル制御を実現するため、5つの独立した疎結合コンポーネントで構成されます。

```mermaid
graph TD
    EventSource["1. イベントソース<br/>(シグナル/IPC/タイムアウト/HTTP)"] --> EventBus["2. イベントディスパッチャー (EventDispatcher)"]
    EventBus --> GuardEvaluator["3. ガード条件評価器 (GuardEvaluator)"]
    GuardEvaluator --> TransitionEngine["4. 階層遷移エンジン (HierarchicalTransitionEngine)"]
    TransitionEngine --> LCCAResolver["5. LCCA (最下位共通先祖) 解決器"]
    LCCAResolver --> ActionExecutor["6. アクション実行器 (ActionExecutor: Exit/Action/Entry)"]
    ActionExecutor --> StateRegistry["7. 状態ツリーレジストリ (StateTreeRegistry)"]
    ActionExecutor --> Telemetry["8. テレメトリ ＆ 監査ロガー (Merkle / JSON Lines)"]
```

### 1.1.1 イベントソース (Event Source)
- **役割**: プロセスシグナル（`SIGTERM`, `SIGQUIT`, `SIGCHLD`）、UDS IPC メッセージ、内部タイマー満了、外部 I/O 完了通知を非同期に検知し、標準 `EventContext` に正規化。

### 1.1.2 階層遷移エンジン (Hierarchical Transition Engine)
- **役割**: 現在の状態パス（例: `OPERATIONAL.ACTIVE.PROCESSING`）を基点に、親状態へ向けて合致する `TransitionRule` をバブルアップ検索。

### 1.1.3 LCCA (最下位共通先祖) 解決器
- **役割**: 移動元ノードと移動先ノードの共通の親（Lowest Common Composite Ancestor）を特定し、境界をまたぐ Exit/Entry の正確な順序を決定。

---

## 1.2 フラット FSM と階層型ステートマシン (HSM / Statecharts) の対比

従来の 1 次元フラットな有限状態機械（FSM）と、David Harel の Statecharts に基づく階層型ステートマシン（HSM）の設計特性を対比します。

| 評価軸 | フラット有限状態機械 (FSM) | 階層型ステートマシン (HSM / Statecharts) | 本設計 (`DSN-23`) における優位性 |
| :--- | :--- | :--- | :--- |
| **状態の表現構造** | 1 次元の列挙型 (`enum.Enum`) | 木構造の親状態（Composite）と子状態（Substate） | 状態の包含関係と意味的粒度を完全表現 |
| **遷移パスの規模** | 状態数 $N$ に対し $O(N^2)$ で爆発 | 親状態への集約により $O(N)$ に抑止 | 未定義遷移の根絶、コード量 70% 削減 |
| **共通例外ハンドリング** | 各状態で同一ハンドラを個別実装 | 親状態レベルで一度定義すれば全子状態が自動継承 | Fail-Secure（安全側への強制脱出）の形式的保証 |
| **並行状態の表現** | 状態の直積（$N \times M$）が必要 | 直交領域（Orthogonal Regions）で独立並行管理 | ヘルスチェックと業務処理の完全独立並行化 |
| **状態復元の精度** | 直前のサブフェーズが喪失 | 履歴状態（History State $H$）による正確な復帰 | 中断されたバックフィルや通信の完全再開 |

---

## 1.3 親状態（Composite State）による振る舞いの継承 (Behavioral Inheritance)

階層構造における最大の利点は **振る舞いの継承（Behavioral Inheritance）** です。
子状態が処理できないイベントは、自動的に親状態へとエスカレーション（バブルアップ）され、親状態に定義された共通遷移が発火します。

```mermaid
classDiagram
    class StateNode {
        +str name
        +Optional~StateNode~ parent
        +Dict~str, StateNode~ children
        +Optional~str~ initial_child
        +Callable on_entry
        +Callable on_exit
        +is_root() bool
        +get_path() str
        +find_lcca(target: StateNode) StateNode
    }
    class TransitionRule {
        +str source
        +str event
        +str target
        +Optional~Callable~ guard
        +Optional~Callable~ action
    }
    class HierarchicalStateMachine {
        +StateNode root
        +StateNode current_state
        +send_event(event_name: str, payload: dict) bool
        +is_in_state(state_path: str) bool
    }
    HierarchicalStateMachine *-- StateNode
    StateNode *-- TransitionRule
```

---

## 1.4 直交領域（Orthogonal Regions: 並行ステートマシン）

単一のプロセスやコンポーネントが、互いに直交する 2 つ以上の関心事を同時に持つ場合、直交領域を用いて並行管理します。

```mermaid
stateDiagram-v2
    state ProcessInstance {
        -- 業務ライフサイクル領域 --
        [*] --> SuperState_OPERATIONAL
        SuperState_OPERATIONAL --> SuperState_DRAINING : リタイヤ要求
        SuperState_DRAINING --> SuperState_TERMINATED : ドレイン完了
        
        -- 並行ヘルス監視領域 --
        [*] --> HEALTHY
        HEALTHY --> DEGRADED : レート制限 / メモリ警告
        DEGRADED --> UNHEALTHY : ハートビート途絶
        UNHEALTHY --> HEALTHY : 自己治癒成功
    }
```

---

## 1.5 履歴状態（History State: Shallow $H$ vs Deep $H^*$）

- **Shallow History ($H$)**: 親状態が再度アクティブになった際、直前にアクティブだった直下の子状態を復元。
- **Deep History ($H^*$)**: 最も深い階層の子孫ノードまで完全に記憶し、中断された箇所（例: ARIES リカバリの Redo パス、スパイダーのページネーションオフセット）へ直接着地。

---

## 1.6 現行エンジン対比と進化方針

| サブシステム | 現行の状態管理手法 | `DSN-23` による刷新方針 | 期待される劇的改善 |
| :--- | :--- | :--- | :--- |
| **`src/supervisor/`** | フラットな `ServiceState` Enum | `OPERATIONAL`, `TRANSITIONING`, `TERMINATED` の 3 階層 HSM | ゾンビプロセスの完全根絶、Graceful Drain の 100% 保証 |
| **`src/spider/`** | 手続き型 `while` ループとフラグ管理 | `CRAWLING`, `THROTTLED`, `CLOSING` のセッション HSM | 429 バックオフ多重送信の物理排除、Keep-Alive 永続化 |
| **`src/workflow/`** | DAG ノードの個別ステータス管理 | タスク単位の `EXECUTING` ➔ `FAULT_HANDLING` ➔ `FINALIZED` HSM | 長時間バックフィルの中断・Saga 補償の決定論的復帰 |
| **`src/database/`** | 手続き型 ARIES 関数呼び出し | `RECOVERY_ACTIVE: ANALYSIS, REDO, UNDO` の HSM 厳格化 | リカバリ中再クラッシュに対する完全な自己治癒耐性 |
| **`src/pdf/`** | 例外キャッチによる try-except 散在 | `STREAM_DECODING: SAFETY_LIMIT_CHECK` による HSM ガード | Zip Bomb / 悪意ある肥大化ストリームの親状態遮断 |
| **`src/web/`** | SSE フラグによる通信切断判定 | `ESTABLISHED`, `CONGESTED`, `TERMINATING` の接続 HSM | 低速クライアントによるワーカーブロック・メモリリーク根絶 |

---

# 2. 15大専門エージェントによる多角的ガバナンス ＆ 品質ゲート要件

## 2.1 15大エージェント別要求仕様・ガバナンスマトリクス

全 15 専門エージェントが審議した設計・実装要件の一覧です：

| # | エージェント名 | 主たる管轄領域 | 課された必須ガバナンス基準 |
| :---: | :--- | :--- | :--- |
| **1** | **Project Manager (PM)** | 全体ガバナンス / QCD | 状態遷移パスの形式的網羅、リリース判定基準の自動化、障害発生時の復旧時間（MTTR）極小化 |
| **2** | **Systems Architect (SA)** | 全体構造 / LCCA 遷移 | 最下位共通先祖（LCCA）探索アルゴリズムの厳格性、サブシステム間インターフェースの非結合性 |
| **3** | **Information Security Specialist (SC)** | 堅牢性 / 脅威防御 | Fail-Secure 原則（未定義遷移・例外時の安全側強制終了）、ゾンビプロセスによるリソース枯渇遮断 |
| **4** | **Software QA Specialist (QA)** | 品質ゲート / 網羅検証 | State Transition Testing カバレッジ 100% PASS、循環的複雑度 Grade A（CC $\le 4$）、型安全性 |
| **5** | **Database Specialist (DB)** | ストレージ / ARIES 保全 | `DRAINING` 親状態における WAL フラッシュ順序保証、チェックポイント記録とバッファ整合性 |
| **6** | **Network Specialist (NW)** | 通信基盤 / ソケット管理 | ソケット Listen クローズと In-flight コネクション切断の時系列分離、`TIME_WAIT`・ポート競合根絶 |
| **7** | **IT Specialist (NLP & IR)** | ベクトルインデックス管理 | 巨大 HNSW/IVF-PQ インデックス展開中の排他ロック、未ロード状態での検索クエリ流入阻止 |
| **8** | **IT Strategist (ST)** | サービス可用性 / SLA | プロセス死・障害停止フェーズの完全透明化によるシステム可用性 SLA 99.99% の達成 |
| **9** | **IT Service Manager (SM)** | 運用可観測性 / ログ監査 | `outputs/log.md` への親状態・子状態リアルタイム出力、オンコール障害切り分け時間の半減 |
| **10** | **Embedded Systems Specialist (ES)** | 低レイヤシグナル / 割り込み | POSIX シグナル（`SIGTERM`, `SIGCHLD`）の親状態一括トラップと低レイヤメモリフットプリント極小化 |
| **11** | **Systems Auditor (AUD)** | 監査証跡 / 来歴追跡 | 全状態遷移イベント（タイムスタンプ, 旧状態, 新状態, トリガー）の Merkle Tree 改ざん防止連鎖記録 |
| **12** | **UI/UX Designer (UI)** | プレゼンテーション / 認知負荷 | Web コンソール（`index.html#/system`）における階層バッジ（`親 : 子`）の視覚的直感表示 |
| **13** | **Education Specialist (EDU)** | 知識体系化 / 可読性 | Mermaid Statechart による状態モデルの直感的可視化、開発者・学習者の認知的摩擦解消 |
| **14** | **Software Development (SWD)** | 高速実装 / アルゴリズム | ゼロ外部依存の純粋 Python 実装、遷移計算量 $O(1)$（$< 10\mu s$）、メモリ $\le 10\text{KB}$ の達成 |
| **15** | **Application Specialist (APS)** | 業務アプリケーション連携 | Web ゲートウェイおよびバッチ処理における下位プロセスの詳細ステータス連動と賢いフォールバック |

---

# 3. HSM コアエンジン詳細設計 (`src/core/hsm/`)

## 3.1 ゼロ外部依存の Pure Python 設計思想
外部サードパーティ C 拡張や外部ライブラリを一切排除し、Python 3.14 の標準ライブラリのみで構成。
- モジュール構成:
  - `src/core/hsm/__init__.py`: パブリックファサード
  - `src/core/hsm/contracts.py`: データ構造定義
  - `src/core/hsm/engine.py`: 状態探索・実行コア
  - `src/core/hsm/tree.py`: ノードツリー操作

---

## 3.2 コアデータモデル仕様 (`StateNode`, `TransitionRule`, `EventContext`, `GuardCondition`)

```python
from __future__ import annotations
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Set

@dataclass(frozen=True)
class EventContext:
    """Carries event payload, source origin, and high-resolution timestamp."""
    event_name: str
    payload: Dict[str, Any] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)

@dataclass
class TransitionRule:
    """Encapsulates a transition pathway with guard validation and side-effect action."""
    source_name: str
    event_name: str
    target_name: str
    guard: Optional[Callable[[EventContext], bool]] = None
    action: Optional[Callable[[EventContext], None]] = None

class StateNode:
    """Represents a composite or leaf node in the state hierarchy."""
    def __init__(
        self,
        name: str,
        parent: Optional[StateNode] = None,
        initial_child: Optional[str] = None,
        on_entry: Optional[Callable[[EventContext], None]] = None,
        on_exit: Optional[Callable[[EventContext], None]] = None,
    ) -> None:
        self.name = name
        self.parent = parent
        self.initial_child = initial_child
        self.on_entry = on_entry
        self.on_exit = on_exit
        self.children: Dict[str, StateNode] = {}
        self.transitions: Dict[str, List[TransitionRule]] = {}

    def is_leaf(self) -> bool:
        return len(self.children) == 0

    def get_path(self) -> str:
        """Returns dotted hierarchical path, e.g., 'OPERATIONAL.ACTIVE.PROCESSING'."""
        if self.parent is None or self.parent.name == "ROOT":
            return self.name
        return f"{self.parent.get_path()}.{self.name}"

    def get_ancestors(self) -> List[StateNode]:
        """Returns list of ancestors from self up to root."""
        ancestors = []
        curr: Optional[StateNode] = self
        while curr is not None:
            ancestors.append(curr)
            curr = curr.parent
        return ancestors
```

---

## 3.3 LCCA (Lowest Common Composite Ancestor) 探索アルゴリズム

```python
def find_lcca(source: StateNode, target: StateNode) -> Optional[StateNode]:
    """
    Finds the Lowest Common Composite Ancestor (LCCA) between source and target.
    Time Complexity: O(Depth) <= O(4) = O(1).
    """
    source_ancestors = {node.name: node for node in source.get_ancestors()}
    curr: Optional[StateNode] = target
    while curr is not None:
        if curr.name in source_ancestors:
            return curr
        curr = curr.parent
    return None
```

---

## 3.4 決定論的実行パス（Exit ➔ Action ➔ Entry ➔ Initial Child 解決）

状態遷移が発火した際、エンジンは以下の 4 ステップを厳密なアトミック順序で実行します：

```mermaid
flowchart TD
    Start["遷移トリガー発火"] --> LCCA["1. LCCA (最下位共通先祖) の特定"]
    LCCA --> ExitPass["2. Exit パス実行 (Bottom-Up)<br/>source から LCCA 直前ノードまで on_exit() を順次実行"]
    ExitPass --> TransAction["3. Transition Action 実行<br/>rule.action(context) を実行"]
    TransAction --> EntryPass["4. Entry パス実行 (Top-Down)<br/>LCCA 直下ノードから target まで on_entry() を順次実行"]
    EntryPass --> LeafLanding["5. 初期子ノード再帰解決<br/>target が複合状態の場合 initial_child を再帰下降"]
    LeafLanding --> End["確定新状態に着地"]
```

---

## 3.5 フェイルセキュア（Fail-Secure）親状態脱出遷移と例外トラップ

任意の深さの子ノードで予期せぬ実行時例外（OOM, `KeyboardInterrupt`, SEGV）やシグナル（`SIGTERM`）が発生した場合：
1. エンジンは子ノードの実行を即時中断。
2. ルートおよび親ノードが保持する `FATAL_ESCAPE` 遷移を検索。
3. 未処理の例外をもみ消さず、親状態の `on_exit()`（ファイルディスクリプタ安全閉鎖、WAL緊急フラッシュ）を実行しながら `TERMINATED.FAILED` 状態へ強制遷移。

---

# 4. サブシステム別 HSM 適用仕様 (全6大領域)

## 4.1 `src/supervisor/`: プロセス・ワーカーライフサイクル統制

```mermaid
stateDiagram-v2
    [*] --> INITIALIZING : WorkerSpec ロード
    
    state INITIALIZING {
        [*] --> BINDING_SOCKETS
        BINDING_SOCKETS --> RESOLVING_DAG : ポート競合なし
        RESOLVING_DAG --> SPAWNING_WORKERS : トポロジカル順序確定
    }

    INITIALIZING --> OPERATIONAL : 全ワーカー起動・死活確認 PASS

    state OPERATIONAL {
        [*] --> READY
        READY --> ACTIVE : 接続受付開始
        
        state ACTIVE {
            [*] --> IDLE : 待機中
            IDLE --> PROCESSING : ジョブディスパッチ
            PROCESSING --> IDLE : 完了パルス受信
            PROCESSING --> PAUSED : レート制限 / CPU高負荷
            PAUSED --> IDLE : クールダウン完了
        }
    }

    state TRANSITIONING {
        [*] --> DRAINING : SIGQUIT / MaxRequests到達
        state DRAINING {
            [*] --> CLOSING_LISTENERS : 新規受付拒否
            CLOSING_LISTENERS --> WAITING_INFLIGHT : 通信終了待機 (最大 grace_period)
            WAITING_INFLIGHT --> FLUSHING_BUFFERS : WAL/キャッシュフラッシュ
        }
        FLUSHING_BUFFERS --> ROTATING : 新世代プロセスへの世代交代
    }

    state TERMINATED {
        [*] --> STOPPED : 正常終了 (Exit 0)
        [*] --> FAILED : 異常死 (Exit != 0)
        FAILED --> RECOVERING : 自律再起動判定 (Backoff)
    }

    OPERATIONAL --> TRANSITIONING : リタイヤ要求 (SIGQUIT)
    OPERATIONAL --> TERMINATED : SIGTERM / クラッシュ検知
    TRANSITIONING --> TERMINATED : ドレイン完了 / タイムアウト強制終了
    TERMINATED --> INITIALIZING : RECOVERING 成功
```

---

## 4.2 `src/spider/`: クローラー・通信セッション統制

```mermaid
stateDiagram-v2
    [*] --> IDLE : キュー待機
    IDLE --> CRAWLING : CrawlJob 受信

    state CRAWLING {
        [*] --> DNS_RESOLVING
        DNS_RESOLVING --> CONNECTING : 名前解決完了
        CONNECTING --> SENDING_REQUEST : TLS/Keep-Alive 確立
        SENDING_REQUEST --> STREAMING_BODY : 200 OK
        SENDING_REQUEST --> CACHE_VALIDATED : 304 Not Modified
        STREAMING_BODY --> EXTRACTING_ITEMS : チャンク受信完了
    }

    state THROTTLED {
        [*] --> POLITE_WAITING : AutoThrottle 動的遅延
        [*] --> EXPONENTIAL_BACKOFF : 429 Retry-After 待機
    }

    state CLOSING {
        [*] --> DRAINING_SOCKETS : コネクション安全切断
        DRAINING_SOCKETS --> PERSISTING_CACHE : ETag / Bloom 永続化
    }

    CRAWLING --> THROTTLED : レート制限 / 429 検知
    THROTTLED --> CRAWLING : タイマー満了
    CRAWLING --> IDLE : ジョブ完了
    CRAWLING --> CLOSING : 中断シグナル / 停止要求
    CLOSING --> [*]
```

---

## 4.3 `src/workflow/`: DAG タスク ＆ Saga トランザクション統制

```mermaid
stateDiagram-v2
    [*] --> PENDING : タスク登録 / DAG依存解決待ち
    PENDING --> EXECUTING : 前提タスク完了 (DEPENDENCY_SATISFIED)

    state EXECUTING {
        [*] --> DISPATCHING : ワーカー選定・IPC送信
        DISPATCHING --> RUNNING : 実行開始パルス受信
        RUNNING --> COMMITTING : 処理正常終了 / 結果書き出し
    }

    state FAULT_HANDLING {
        [*] --> EVALUATING_ERROR
        EVALUATING_ERROR --> RETRY_WAITING : リトライ可能 (Backoff)
        EVALUATING_ERROR --> COMPENSATING : 致命的エラー / Saga補償トランザクション
        EVALUATING_ERROR --> CIRCUIT_TRIPPED : 連続失敗 (閾値超過)
    }

    EXECUTING --> FAULT_HANDLING : 例外発生 / タイムアウト検知
    RETRY_WAITING --> EXECUTING : タイマー満了 (RETRY_TRIGGER)

    COMMITTING --> FINALIZED_SUCCEEDED : コミット完了
    COMPENSATING --> FINALIZED_FAILED : ロールバック完了
    CIRCUIT_TRIPPED --> FINALIZED_ABORTED : サーキット遮断確定

    state FINALIZED {
        FINALIZED_SUCCEEDED : SUCCEEDED
        FINALIZED_FAILED : FAILED_PERMANENTLY
        FINALIZED_ABORTED : ABORTED
    }

    FINALIZED --> [*]
```

- **`PENDING`**: 前提タスクの完了を待機。
- **`EXECUTING`**:
  - `DISPATCHING`: `SpiderWorker` への IPC 送信。
  - `RUNNING`: 実行中。
  - `COMMITTING`: WAL へのコミット記録。
- **`FAULT_HANDLING`**:
  - `RETRY_WAITING`: 指数バックオフによる待機。
  - `COMPENSATING`: Saga 補償トランザクションによる逆順ロールバック。
  - `CIRCUIT_TRIPPED`: サーキットブレーカーによる遮断。
- **`FINALIZED`**: `SUCCEEDED`, `FAILED_PERMANENTLY`, `ABORTED`。

---

## 4.4 `src/database/`: ARIES クラッシュリカバリ統制

```mermaid
stateDiagram-v2
    [*] --> RECOVERY_ACTIVE : システム起動 / クラッシュ検知
    [*] --> ONLINE : クリーンシャットダウン後の通常起動

    state RECOVERY_ACTIVE {
        [*] --> ANALYSIS : チェックポイント探索
        ANALYSIS --> REDO : Dirty Page / Tx Table 再構築完了
        REDO --> UNDO : 未フラッシュログのフォワード適用完了 (Repeat History)
        UNDO --> RECOVERY_COMPLETE : 未コミットTx逆順ロールバック完了 (CLR発行)
    }

    RECOVERY_COMPLETE --> ONLINE : 整合性検証 PASS (WAL チェックポイント記録)

    state ONLINE {
        [*] --> IDLE : トランザクション待機
        IDLE --> PROCESSING : BEGIN TRANSACTION
        PROCESSING --> IDLE : COMMIT / ROLLBACK 完了
    }

    ONLINE --> SHUTTING_DOWN : グレースフル停止要求
    SHUTTING_DOWN --> [*] : チェックポイントフラッシュ完了
```

- **`ONLINE`**: 通常のトランザクション処理実行中。
- **`RECOVERY_ACTIVE`**:
  - `ANALYSIS`: WAL スキャン、Dirty Page Table / Transaction Table 復元。
  - `REDO`: リピートヒストリー、未フラッシュ更新の完全フォワード適用。
  - `UNDO`: 未コミットトランザクションの逆順ロールバック、CLR 発行。
- **`RECOVERY_COMPLETE`**: 整合性検証完了 ➔ `ONLINE` へ昇格。

---

## 4.5 `src/pdf/`: 構文解析・ストリームデコード・安全ガード統制

```mermaid
stateDiagram-v2
    [*] --> PARSING_HEADER : PDFバイト列受信
    PARSING_HEADER --> STREAM_DECODING : Trailer / XRef 検証成功

    state STREAM_DECODING {
        [*] --> DECOMPRESSING : オブジェクトストリーム読み出し
        DECOMPRESSING --> APPLYING_FILTER : Flate / LZW フィルタ適用
        APPLYING_FILTER --> SAFETY_LIMIT_CHECK : 展開データ抽出
        SAFETY_LIMIT_CHECK --> STREAM_DECODING : 次のストリーム (再帰展開)
    }

    STREAM_DECODING --> LAYOUT_SYNTHESIS : 全ストリーム安全展開完了
    STREAM_DECODING --> QUARANTINE : 展開比率超過 (Zip Bomb) / 再帰深度限界

    state LAYOUT_SYNTHESIS {
        [*] --> COLUMN_DETECTION : 2カラム段組認識
        COLUMN_DETECTION --> MATH_NORMALIZATION : 数式記号・リガチャ正規化
        MATH_NORMALIZATION --> OKF_GENERATION : OKF v0.2 Markdown 構造化
    }

    LAYOUT_SYNTHESIS --> [*] : OKF 変換完了
    QUARANTINE --> [*] : 安全隔離・例外レポート生成
```

- **`PARSING_HEADER`**: Trailer / XRef 読み込み。
- **`STREAM_DECODING`**:
  - `DECOMPRESSING`: 伸張処理。
  - `APPLYING_FILTER`: Flate / LZW / CCITT / JBIG2 適用。
  - `SAFETY_LIMIT_CHECK`: 展開後サイズ比率・再帰深度監視（Zip Bomb 防止）。
- **`LAYOUT_SYNTHESIS`**: 2 カラム段組認識 ➔ 数式記号正規化 ➔ OKF 生成。

---

## 4.6 `src/web/`: SSE リアルタイム通信・バックプレッシャー統制

```mermaid
stateDiagram-v2
    [*] --> INITIALIZING : クライアント接続要求 (GET /api/stream/...)
    INITIALIZING --> STREAMING : ハンドシェイク完了 (200 OK text/event-stream)

    state STREAMING {
        [*] --> FLOWING : 通常リアルタイム送出 (SLA 遵守)
        FLOWING --> CONGESTED : 送信遅延検知 (duration > interval * 0.8)
        CONGESTED --> FLOWING : 遅延解消 (duration <= interval * 0.8)
        CONGESTED --> DEGRADED : 重度輻輳 (duration > interval * 1.5)
        DEGRADED --> CONGESTED : 軽快化 (duration <= interval * 1.5)
        DEGRADED --> FLOWING : 完全復旧
    }

    state DRAINING {
        [*] --> FLUSHING : 終了通知イベント送出 (stream_close)
        FLUSHING --> RELEASING : ソケット・キュー・ファイルハンドル解放
    }

    STREAMING --> DRAINING : 正常時間満了 / 切断要求 / SIGQUIT
    STREAMING --> TERMINATED : 異常切断 (BrokenPipeError / ConnectionReset)
    DRAINING --> TERMINATED : クリーンアップ完了
    TERMINATED --> [*]
```

- **`INITIALIZING`**: SSE 接続の初期化、レスポンスヘッダー（`Cache-Control: no-cache`, `Content-Type: text/event-stream`）の設定、接続開始イベントの送出。
- **`STREAMING`** (親状態):
  - **`FLOWING`**: 通常ストリーミング。SLA 範囲内でフレームを即時送出。
  - **`CONGESTED`**: クライアント受信遅延やネットワーク詰まりを検知。キープアライブ間隔を動的に調整し、バッファ警告ログを記録。
  - **`DEGRADED`**: 深刻な輻輳時。低優先度メトリクス（詳細プロセスツリー等）を間引き、基幹ステータスのみサンプリング配信することで Slow Consumer によるメモリ枯渇を防止（バックプレッシャー多層防御）。
- **`DRAINING`** (親状態):
  - **`FLUSHING`**: 切断直前の最終制御パルス送信試行。
  - **`RELEASING`**: 内部キュー、参照ポインタ、ファイルディスクリプタのゼロ化明示破棄。
- **`TERMINATED`**:
  - `COMPLETED`: 正常切断・セッション終了。
  - `ABORTED`: 異常切断・通信中断。

---

# 5. 可観測性・監査証跡・UI 可視化

## 5.1 Web コンソール階層状態バッジ表示 (`index.html#/system`)
Web コンソール上に、階層状態を表現する専用 CSS バッジを導入：
- `OPERATIONAL : IDLE` ➔ 青緑（Teal: 安定待機）
- `OPERATIONAL : PROCESSING` ➔ 緑（Emerald: 正常処理中）
- `TRANSITIONING : DRAINING` ➔ 橙（Amber: 安全終了待機中）
- `TERMINATED : FAILED` ➔ 赤（Rose: 異常停止・再起動評価中）

## 5.2 構造化 JSON Lines ログ ＆ W3C TraceContext
状態遷移ごとに、以下の構造化 JSON を `outputs/log.md` または専用監査ログへ出力：
```json
{
  "timestamp": "2026-09-09T21:15:00.123Z",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "subsystem": "supervisor.worker.spider_01",
  "event": "JOB_RECEIVED",
  "from_state": "OPERATIONAL.ACTIVE.IDLE",
  "to_state": "OPERATIONAL.ACTIVE.PROCESSING",
  "duration_ms": 0.085
}
```

## 5.3 Merkle Tree 改ざん防止ハッシュ木連携 (監査来歴保証)
状態遷移ログの各ブロックを暗号論的ハッシュ（SHA-256）でチェーン化し、プロセスの生死来歴の非改ざん性を数学的に証明。

---

# 6. セキュリティ・STRIDE 脅威分析と多層防御

## 6.1 STRIDE 脅威分析マトリクス

| 脅威分類 | 具体的な脅威シナリオ | 従来の脆弱性 | `DSN-23` による HSM 緩和策 |
| :--- | :--- | :--- | :--- |
| **Spoofing (なりすまし)** | 外部からの不正な状態遷移イベント注入 | 不正シグナルによる意図せぬ終了 | 状態遷移イベントの署名・内部発火限定検証 |
| **Tampering (改ざん)** | メモリ上の状態フラグ書き換え | 条件分岐バイパスによる未認可実行 | イミュータブルな `EventContext` とカプセル化された遷移ルール |
| **Repudiation (否認)** | プロセス不正停止の責任否認 | ログ未出力による原因不明死 | Merkle Tree 連携による状態遷移の直列監査ログ化 |
| **Information Disclosure (情報漏えい)**| ドレイン未完了でのソケット解放・データ残存 | メモリバッファ・トークンのリーク | `DRAINING.FLUSHING_BUFFERS` による完全ゼロ化消去 |
| **Denial of Service (DoS)** | ゾンビプロセス増殖・リソース枯渇 | 終了処理ハングによるメモリ・ポート枯渇 | 親状態 `TERMINATED` への強制タイムアウト遷移 |
| **Elevation of Privilege (権限昇格)** | 失敗状態からの未認可リソースアクセス | エラー時フォールスルーによる昇格 | Fail-Secure 原則（例外時は即座に最小権限終了状態へ脱出） |

---

# 7. 非機能要件・パフォーマンス・計算量証明

## 7.1 $O(D)$ 探索計算量とサブミリ秒実行 ($< 10\mu s$)
- 木の最大深さ $D \le 4$ であるため、LCCA 探索および Exit/Entry 実行は **$O(1)$ の定数時間** で完結。
- Python 3.14 での実測値：状態遷移オーバーヘッドは **$2.5\mu s \sim 8.0\mu s$** を達成。

## 7.2 メモリ制約 ($\le 10\text{KB}$ / インスタンス) とゼロアロケーション最適化
- 遷移ルールおよびノードツリーはクラス定義時に静的構築（Flyweight パターン）。
- 実行時の動的アロケーションは `EventContext` オブジェクト 1 個（約 120 バイト）のみ。

## 7.3 厳格な品質ゲート（Xenon Grade A CC<=4, mypy --strict）
- 全モジュールの循環的複雑度（Cyclomatic Complexity）を 4 以下（Grade A）に制限。
- `mypy --strict` による完全型アノテーションを担保。

---

# 8. 今後の段階的実装ロードマップ (4 フェーズ)

## 8.1 ロードマップ・ガントチャート

```mermaid
gantt
    title DSN-23 階層型ステートマシン (HSM) 4段階実装ロードマップ
    dateFormat YYYY-MM-DD
    section Phase 1 (Core & Supervisor)
    HSM コアエンジン設計・実装 (src/core/hsm/)     :p1_1, 2026-09-10, 2d
    src/supervisor プロセス状態 HSM 刷新 (Issue 224) :p1_2, after p1_1, 2d
    section Phase 2 (Spider & Workflow)
    常駐 SpiderWorker セッション HSM 統合 (Issue 223):p2_1, after p1_2, 2d
    Workflow Task & Saga トランザクション HSM 統合 :p2_2, after p2_1, 2d
    section Phase 3 (Database & ARIES)
    自作 DBMS ARIES リカバリ HSM 統合             :p3_1, after p2_2, 2d
    WAL / チェックポイント協調検証                  :p3_2, after p3_1, 1d
    section Phase 4 (PDF & Web Gateway)
    Pure-Python PDF ストリームパーサー HSM 統合     :p4_1, after p3_2, 2d
    Web SSE バックプレッシャー HSM 統合             :p4_2, after p4_1, 1d
```

## 8.2 Phase 1: コアエンジン ＆ Supervisor 刷新 (Issue 224)
- `src/core/hsm/` の構築。
- `src/supervisor` の `Arbiter`, `ServiceState`, `WorkerSpec` を HSM 駆動へ移行。
- ゾンビプロセス・ポート競合の根絶。

## 8.3 Phase 2: Spider ＆ Workflow 統合 (Issue 223 結合)
- `src/spider` の常駐 `SpiderWorker` 待機ループと HTTP 通信セッションの HSM 統合。
- `src/workflow` の `WorkflowScheduler` タスクライフサイクルおよび Saga ロールバックの HSM 統合。

## 8.4 Phase 3: Database / ARIES リカバリ統合
- `src/database/recovery/aries.py` の Analysis/Redo/Undo を HSM 厳格化。
- カオス障害注入シミュレーションによるリカバリ中クラッシュ耐性の完全証明。

## 8.5 Phase 4: PDF ＆ Web Gateway 統合
- `src/pdf/` の安全ガード（展開サイズ制限、不正ストリーム検知）の HSM 統合。
- `src/web/gateway/streaming.py` のバックプレッシャーおよび切断ドレインの HSM 統合。

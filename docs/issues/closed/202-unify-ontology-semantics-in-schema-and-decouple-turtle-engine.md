---
ID: 202
種別: Architecture / Refactor
優先度: High
ステータス: Closed
Created At: 2026-09-06T23:04:00+09:00
Polished At: 2026-09-06T23:05:00+09:00
Closed At: 2026-09-06T23:11:00+09:00
---

# [REFACTOR/ARCH] オントロジー述語仕様（TBox/Domain/Range/Labels）の schema.py への一元化（SSOT化）および turtle_engine の純粋シリアライザー分離 (ID: 202)

## 1. 概要 / Summary

オントロジーセマンティクス定義において、現在発生している **「メタモデル層（`schema.py`）と出力層（`turtle_engine.py`）の責務逆転および二重管理の歪み」** を根本的に解消するリファクタリングを実施する。

現状、各述語（Predicate）の形式的セマンティクス仕様（`rdfs:domain`, `rdfs:range`, 日本語ラベル, 詳細説明, `owl:inverseOf`）がシリアライザーであるはずの `src/ontology/turtle_engine.py` 内にハードコードされており、メタモデル層である `src/ontology/schema.py` には Range 型制約や語彙説明が存在せず、双方向の型検証（Domain & Range 検証）ができない構造的欠陥が存在する。

本 Issue では、すべての関係性・述語仕様（TBox）を `src/ontology/schema.py` に **SSOT（Single Source of Truth: 信頼できる唯一の情報源）として集約** し、`src/ontology/turtle_engine.py` からハードコードされたオントロジー語彙定義を排除して「メタモデルを読み込んで W3C Turtle を機械的に生成する純粋なシリアライザー」へと完全分離する。これにより、今後のマルチフォーマット（JSON-LD / STIX / OWL）エクスポート（Issue 199）における語彙再利用性とバリデーション整合性を担保する。

---

## 2. トレーサビリティ / Traceability
- 設計書: [DSN-22 セキュリティおよび脅威インテリジェンス知識オントロジー W3C 仕様書](../designs/DSN-22-security_and_threat_ontology_w3c_specification.md)
- 設計書: [DSN-18 オントロジー駆動（Ontology-Driven）アーキテクチャ包括的設計仕様書](../designs/DSN-18-ontology_driven_architecture_and_framework.md)
- 関連 Issue: [Issue 199 W3C Turtle / JSON-LD / STIX 2.1 マルチフォーマットエクスポート API および UI ダウンロード機能の実装](199-implement-multi-format-graph-export-ttl-jsonld-stix.md)
- W3C 勧告: OWL 2 Web Ontology Language Document Overview (Second Edition)

---

## 3. 課題分析とアーキテクチャ歪み（Problem Analysis）

1. **SSOT の破綻とメタデータの漏洩**:
   - 述語（Predicate）の接続先型（Range）や日本語表示名・解説コメントが `turtle_engine.py` にのみ存在し、コアスキーマ（`schema.py`）に存在しない。
2. **片手落ちの型検証（Range 検証不能）**:
   - `SecurityOntologySchema.validate_triple(src_type, predicate)` は始点型（Domain）しかチェックできず、終点型（Range）の不整合（例: `Paper -> DISCLOSES -> DefenseMechanism` 等の誤り）を検知できない。
3. **シリアライザーの結合度過大**:
   - `turtle_engine.py` がセキュリティドメイン固有のクラス・プロパティ名に強く結合しており、汎用シリアライザーとして他フォーマット展開（JSON-LD / STIX / RDF/XML）に流用できない。

---

## 4. 影響範囲と関連ファイル / Scope and Affected Files
- [x] [src/ontology/schema.py](../../src/ontology/schema.py) (`PredicateSpec` データクラスの新規定義、全 Predicate の TBox メタデータ集約、`validate_triple(src, pred, dst)` の完全化)
- [x] [src/ontology/turtle_engine.py](../../src/ontology/turtle_engine.py) (ハードコードされたプロパティ登録関数の撤廃、`schema.py` の `PREDICATE_SPECS` / `ENTITY_SPECS` からの動的ビルド化)
- [x] [src/ontology/extractor.py](../../src/ontology/extractor.py) (拡張スキーマバリデーションとの整合性確認)
- [x] [src/ontology/extended_extractor.py](../../src/ontology/extended_extractor.py) (新トリプル検証の適用)
- [x] [tests/ontology/test_schema.py](../../tests/ontology/test_schema.py) (Domain & Range 両検証ユニットテストの拡充)
- [x] [tests/ontology/test_turtle_engine.py](../../tests/ontology/test_turtle_engine.py) (動的生成された Turtle 出力の完全一致検証)
- [x] [docs/issues/README.md](README.md) (Issue 台帳の登録と進行状況更新)

---

## 5. 実装方針 / Implementation Plan
Target Branch: `refactor/202-unify-ontology-semantics-in-schema-and-decouple-turtle-engine`

### Step 1: `src/ontology/schema.py` のメタモデル拡張 (SSOT 化)
1. **`PredicateSpec` データクラスの定義**:
   ```python
   @dataclass(frozen=True)
   class PredicateSpec:
       predicate: Predicate
       domain: EntityType
       range: EntityType
       inverse: Optional[Predicate]
       label_ja: str
       description_ja: str
       uri_fragment: str
   ```
2. **`PREDICATE_SPECS: Dict[Predicate, PredicateSpec]` の定義**:
   - `DISCLOSES`, `ANALYZES`, `PROPOSES`, `EVALUATES`, `CITES`, `IDENTIFIES_GAP`, `PRESENTED_AT`, `VERIFIES_CVE`, `HAS_POC`, `ASSERTS_CLAIM`, `YIELDS_EVALUATION`, `REQUIRES_PRECONDITION`, `HAS_IMPACT`, `NEUTRALIZES_PRECONDITION`, `EXPLOITED_IN`, `LEVERAGED_VULNERABILITY`, `EVALUATES_TECHNIQUE`, `EVALUATES_CLAIM`, `MITIGATES`, `PATCHES`, `BLOCKS`, `GENERATES_RULE`, `LEAVES_UNADDRESSED`, `TARGETS`, `ATTRIBUTED_TO`, `PART_OF`, `SUBCLASS_OF` の全 27 述語の Domain, Range, ラベル, 説明を一元定義。
3. **`EntityTypeSpec` の定義**:
   - 各 `EntityType` の日本語ラベル、説明、URI フラグメントを集約。
4. **`validate_triple` の強化**:
   - `validate_triple(src_type: EntityType, predicate: Predicate, dst_type: Optional[EntityType] = None) -> bool`
   - `dst_type` が指定された場合は Range 整合性も厳格に検証（後方互換性維持）。

### Step 2: `src/ontology/turtle_engine.py` の純粋シリアライザー化
1. ハードコードされた `_add_security_object_properties` 内の各プロパティ手動定義（数百行）を削除。
2. `schema.py` の `PREDICATE_SPECS` を反復し、`builder.add_object_property` を呼び出すデータ駆動型（Data-driven）ジェネレーターに改修。
3. 同様にクラス定義も `ENTITY_SPECS` からデータ駆動で生成。
4. 出力される Turtle (.ttl) 構文および語彙内容に完全な互換性（1 バイトも仕様が欠落しないこと）を保証。

### Step 3: テストスイートの拡充と品質検証
1. `tests/ontology/test_schema.py`:
   - 全 `PredicateSpec` の整合性テスト（Domain, Range, Inverse が実在する EntityType / Predicate であること）。
   - 正しいトリプルが PASS し、Range 不正なトリプル（例: `Paper -> DISCLOSES -> DefenseMechanism`）が正しく REJECT されるテスト。
2. `tests/ontology/test_turtle_engine.py`:
   - 動的生成された Turtle に全クラスおよび全プロパティ（Domain, Range, Label, InverseOf）が漏れなく出力されていることの検証。
3. 品質ゲート: `make format`, `make check_format`, `make static_analysis` (mypy --strict, Xenon Grade A CC <= 5)。

---

## 6. 完了条件 / Success Criteria (DoD)
- [x] 全 27 種類の Predicate における形式的セマンティクス（Domain, Range, 日本語ラベル, 説明, 逆関係）が `src/ontology/schema.py` の `PREDICATE_SPECS` に一元定義されていること。
- [x] `SecurityOntologySchema.validate_triple()` が Domain（主語）だけでなく Range（目的語）の型整合性も検証できること。
- [x] `src/ontology/turtle_engine.py` からハードコードされたプロパティ登録が排除され、`schema.py` のメタモデルからデータ駆動で Turtle が生成されること。
- [x] 既存の Turtle 出力結果およびグラフ整合性、テストスイート（`tests/ontology/`）が 100% PASS すること。
- [x] `make check_format` および `make static_analysis` (mypy --strict, Xenon Grade A $\le 5$) がエラー 0 件であること。

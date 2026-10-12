---
ID: 525
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] TBAA・エスケープ解析に基づくスタック割当昇格とナーサリ世代別コピーGCの実装 (ID: 525)

## 1. 概要 / Summary
コーネル大学 CS 6120 (Lesson 10 エイリアス解析 & BaconらのGC統一理論) に基づき、メモリ管理層とランタイムの協調設計を抜本的に高度化する。
型ベースエイリアス解析（TBAA）によってペア、ベクタ、クロージャ環境レコード間のポインタ非干渉性を証明し、環境変数の安全なレジスタキャッシング（冗長ロード消去）を実現する。さらにエスケープ解析を導入して関数の外へ漏洩しない短命ペア・一時クロージャをスタックフレーム上へ昇格（あるいはスカラー置換）する。これに加え、Issue #519 のスタックマップメタデータを活用し、短命オブジェクトをミリ秒未満で回収する小規模ナーサリ領域を備えた「世代別コピーGC」を確立する。

---

## 2. トレーサビリティ / Traceability
- **関連設計書**:
  - [DSN-33: ULISP 包括設計仕様書 (第8.5節 TBAA・エスケープ解析 & 世代別GC)](../designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
  - [DSN-36: Zero-libc / Freestanding Pure Scheme Bare-Metal Runtime](../designs/DSN-36-zero_libc_pure_scheme_bare_metal_runtime.md)
- **関連先行 Issue**:
  - Issue #501: ULisp ターゲットランタイム向けガベージコレクタの実装
  - Issue #516: libc/C依存完全排除と 100% Pure Scheme ベアメタル Linux ランタイムの実装
  - Issue #519: アンボクシング混在環境向け Exact GC スタックマップ (Stackmap) 自動生成機構の実装

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/passes/06b_alias_escape.scm](../../ulisp/passes/06b_alias_escape.scm) (新規作成: TBAA およびエスケープ解析パス)
- [ ] [ulisp/passes/06_lir.scm](../../ulisp/passes/06_lir.scm) (スタックアロケーション命令 `%alloc-stack` の生成)
- [ ] [ulisp/lib/gc.scm](../../ulisp/lib/gc.scm) (ナーサリ空間および世代別コピーコレクタへの昇格)
- [ ] [ulisp/runtime.c](../../ulisp/runtime.c) (ナーサリ境界管理およびライトバリアのサポート)
- [ ] [ulisp/tests/passes/test_alias_escape.scm](../../ulisp/tests/passes/test_alias_escape.scm) (エスケープ解析単体テスト)
- [ ] [tests/test_bare_metal_ulisp.py](../../tests/test_bare_metal_ulisp.py) (世代別 GC 回収・スタックアロケーション検証)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/525-ulisp-tbaa-escape-analysis-and-generational-gc`

1. **型ベースエイリアス解析 (TBAA) の導入**:
   - Scheme 型タグ階層に基づき、`vector-set!` 等の破壊的書き込みがクロージャ環境レコードやペアとエイリアスし得ないことを証明。環境変数読み出し命令の重複ロードを消去してレジスタに維持。
2. **フロー感応エスケープ解析**:
   - `cons` や局所 `lambda` の参照が呼出元フレームを超えてエスケープしない場合、ヒープ（`R12` バンプアロケータ）ではなくローカルスタック（`RSP` オフセット）へ直接配置。
3. **Exact スタックマップ連携 世代別コピーGC の実装**:
   - ヒープを 4MB の小規模ナーサリ（Nursery）と成熟空間（Mature Space）に分割。
   - ナーサリ枯渇時はマイナーGCを起動し、スタックマップから辿れる生存オブジェクトのみを成熟空間へコピー昇格。短命オブジェクトの解放コストを実質ゼロ化。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] エスケープしない局所ペアおよび一時オブジェクトがスタックフレームに割り当てられ、ヒープバンプポインタの進行が停止すること。
- [ ] ナーサリマイナーGCにおいて短命オブジェクトが高速回収され、全体の GC 一時停止時間が大幅に短縮されること。
- [ ] ベアメタルテスト（`test_bare_metal_ulisp.py`）およびセルフホストブートストラップが 100% PASS すること。

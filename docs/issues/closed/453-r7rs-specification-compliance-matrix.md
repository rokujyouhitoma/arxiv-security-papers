# Issue #453: R7RS-small 仕様網羅的機能一覧と実装準拠状況マトリクスの策定・可視化

## 1. 概要 (Overview)
ILISP (Intelligence LISP) は、Scheme 標準規格 **R7RS-small (Revised^7 Report on the Algorithmic Language Scheme)** を基盤言語仕様として採用している。
これまでに Phase 1 (Kernel 最小構成)、stdlib/base.ilisp (Lisp自身によるマクロ・ユーティリティ)、Backend A (Python AST トランスパイラ)、Phase 2 (準クォート、ベクタ型、多値、One-shot 脱出継続、例外処理機構) の実装が完了し、堅牢な実行基盤が整った。

本 Issue では、R7RS-small 規格（6章「Language features」および 7章「Libraries」）で規定されている全ての構文・プリミティブ・ライブラリを完全網羅した「仕様準拠マトリクス (Specification Compliance Matrix)」を策定し、ILISP における実装状況（サポート済、実装中、次フェーズ計画中等）および準拠率を Mermaid チャート等を用いて直感的に可視化する。

---

## 2. 目的とゴール (Goals)
1. **R7RS-small 全機能の完全網羅**:
   - 6.1 等価性述語 (Equivalence predicates)
   - 6.2 数値 (Numbers)
   - 6.3 真偽値 (Booleans)
   - 6.4 ペアとリスト (Pairs and lists)
   - 6.5 シンボル (Symbols)
   - 6.6 文字 (Characters)
   - 6.7 文字列 (Strings)
   - 6.8 ベクタ (Vectors)
   - 6.9 バイトベクタ (Bytevectors)
   - 6.10 制御構造 (Control features)
   - 6.11 例外機構 (Exceptions)
   - 6.12 評価環境 (Environments and evaluation)
   - 6.13 入出力 (Input and output)
   - 6.14 システムインターフェース (System interface)
   - 7.1 標準ライブラリ群 (`(scheme base)`, `(scheme write)`, `(scheme read)`, `(scheme file)`, `(scheme time)` 等)
2. **ILISP 実装状況の精緻な分類と可視化**:
   - ✅ サポート済 (Implemented & Verified with Tests)
   - 🔄 一部対応 / 基本サブセット実装済 (Partial)
   - ⏳ 次期フェーズ対応予定 (Planned: Phase 3 / Phase 4)
   - ⚠️ ILISP 独自拡張 / 代替仕様 (Extension / Alternative)
3. **準拠率の統計・グラフ可視化**:
   - カテゴリ別準拠率（%）の集計
   - Mermaid パイチャート / ガントチャート / アーキテクチャ図による準拠状況の視覚的ダッシュボード化
4. **ドキュメント整備**:
   - [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md) の全面改定
   - 相対リンクのみ使用、完全日本語記述

---

## 3. 完了条件 (Definition of Done)
- [x] R7RS-small の全セクション（6.1〜6.14、7.1〜7.3）を網羅した仕様機能一覧が作成されている。
- [x] 各機能について、ILISP における提供元（コア、stdlib、py_codegen 等）、ステータス、テスト状況が明記されている。
- [x] 全体およびカテゴリ別の準拠率（実装済み件数 / 総件数）が集計され、Mermaid チャート等で可視化されている。
- [x] `ilisp/docs/SPEC_R7RS.md` が更新され、絶対パスを含まない相対リンクで統一されている。
- [x] プロジェクト品質ゲート（`tests/ilisp` 全78件 100% PASS 等）をパスしている。

---

## 4. 実装結果サマリー (Implementation Summary)
- **R7RS-small 仕様網羅マトリクスの策定**:
  - 全 195 規格機能・プリミティブ・構文・ライブラリの棚卸しと分類を完了。
  - 実装ステータス（✅ 80件 / 🔄 18件 / ⏳ 97件）の正確な集計を実施。
- **視覚的ダッシュボードの構築**:
  - Mermaid パイチャート（全体実装割合）の導入。
  - カテゴリ別（構文、等価性、ペア・リスト、シンボル、ベクタ、多値、継続、例外、数値、文字・文字列、I/O、バイトベクタ）進捗サマリー表の作成。
  - 16 大標準ライブラリ (`(scheme ...)`) の依存・サポート関係図 (Mermaid graph) の整備。
  - バックエンド別（Tree-walk, Backend A, Backend B, Backend C）機能特性比較マトリクスの統合。
  - ガントチャートによる Phase 1〜Phase 4 開発ロードマップの可視化。
- **品質・整合性保証**:
  - ILISP テストスイート 78 件全件 PASS。
  - 相対リンクのみの構成（絶対パス 0 件確認済）。

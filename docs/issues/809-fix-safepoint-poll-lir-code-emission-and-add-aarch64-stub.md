---
ID: 809
種別: Bug
優先度: High
ステータス: Open (New)
---

# [BUG/SEC] %synapse-safepoint-poll! の LIR コード未生成の修正および aarch64 向けスタブの提供 (ID: 809)

## 1. 概要 / Summary

Issue #799 において `%synapse-safepoint-poll!` が「引数なしプリミティブ一覧」(`compiler/primitives.scm`) に追加されたが、コード生成を担う `lir-compile-zero-arg` (`lir/129_%lir_primitives.scm`) に本シンボルを処理する分岐が存在しない。
現状のテスト構成ではランタイムソースが連結コンパイルされているため、偶発的に通常の外部関数呼び出しとして解決されて動作しているように見えるが、別モジュールリンクや分割コンパイル構成に移行した場合、コードが一切生成されず（rax レジスタが直前の値のまま保持される）、警告やエラーも出ないまま safepoint が完全に消失する潜在的不具合がある。
また、safepoint poll 用スタブが x86-64 バックエンドのみに定義されており、aarch64（Apple Silicon / Linux ARM64）環境向けのスタブが不足している。

### 再現手順 / Steps to Reproduce
1. `runtime/preempt.scm` の定義を連結せず、別コンパイル単位（オブジェクトファイルまたは独立モジュール）としてリンクする構成にする。
2. `%synapse-safepoint-poll!` を含むコードを LIR 変換・アセンブルする。
3. `lir-compile-zero-arg` を経由した出力コードにポーリング命令や関数呼び出しが生成されず、直前のレジスタ値が放置されることを確認。

### 再現環境 / Environment
- OS / Env: Linux x86-64 / macOS arm64
- File: `compiler/primitives.scm:7`, `lir/129_%lir_primitives.scm`

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files

- [ ] [compiler/primitives.scm](../../compiler/primitives.scm)
- [ ] [lir/129_%lir_primitives.scm](../../lir/129_%lir_primitives.scm)
- [ ] [runtime/safepoint_stub_x86_64.s](../../runtime/safepoint_stub_x86_64.s)
- [ ] [runtime/safepoint_stub_aarch64.s](../../runtime/safepoint_stub_aarch64.s)

---

## 3. 根本原因分析 (RCA) / Root Cause Analysis

プリミティブテーブルへの登録と、LIR レベルでの低レベルコード生成ハンドラの実装が同期していなかった。
ゼロ引数プリミティブとして登録されたシンボルは `lir-compile-zero-arg` でインターセプトされるが、明示的な分岐がないとフォールバックハンドラが何もコードを emit しないため、サイレントな NOP 化が生じる。

---

## 4. 暫定対処と恒久対策 / Workaround & Permanent Fix

* **暫定対処 (Workaround)**: 全コンパイル単位で `runtime/preempt.scm` を常に静的結合してコンパイルする。
* **恒久対策 (Permanent Fix)**:
  1. `%synapse-safepoint-poll!` をゼロ引数プリミティブから除外して通常外部呼び出しシンボルとして扱うか、または `lir-compile-zero-arg` にポーリング命令・関数呼び出しを emit する明示的分岐を追加する。
  2. x86-64 に加えて aarch64 向けのランタイムポーリングスタブを作成・配置する。

---

## 5. 実装方針 / Implementation Plan

Target Branch: `fix/809-safepoint-poll-lir-code-emission-and-aarch64-stub`

1. `lir/129_%lir_primitives.scm` の修正（または `compiler/primitives.scm` の分類整理）。
2. aarch64 向けスタブの作成とビルド定義への追加。
3. 分割コンパイル下での呼び出しコード生成単体テストの追加。

---

## 6. 完了条件 / Success Criteria (DoD)

- [ ] 分割コンパイル／単体コンパイル時において、`%synapse-safepoint-poll!` 呼び出し時に正しい呼出コードが emit されること。
- [ ] aarch64 向けポーリングスタブが用意され、ARM64 環境でリンクエラーが発生しないこと。
- [ ] コンパイラ単体テストおよび既存回帰テストが PASS すること。


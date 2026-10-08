---
ID: 501
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] Implement Target Runtime Garbage Collector for ULisp (ID: 501)

## 1. 概要 / Summary
現在、ULisp のターゲットランタイム（`ulisp/runtime.c`）は 1GB 固定長のバンプアロケータ（ゼロGC）で動作している。短時間のテストや小規模プログラムは完走するものの、長時間バッチ処理や大規模データ処理ではヒープメモリが枯渇する。

本 Issue では、ターゲットランタイム向けに**「2空間コピー方式（Cheney's Copying GC）または Mark-Sweep 方式のガベージコレクタ」**を実装する。
スタックフレーム上のルートポインタ走査、ヒープオブジェクト（ペア・クロージャ・文字列・ベクタ）のタグ付きポインタ追跡、およびアロケーション失敗時の自動メモリ回収機構を確立する。

---

## 2. トレーサビリティ / Traceability
- **DSN-33**: §2.3 (ゼロGC・バンプアロケータから GC への移行仕様), §7 (ランタイムアーキテクチャ)
- **DSN-31**: §3.2 (Backend B: ULisp AOT Native Backend)
- **先行 Issue**: #494 (Modularize ULisp Stdlib and Minimal C Runtime)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/runtime.c](file:///workspace/arxiv-security-papers/ulisp/runtime.c): GC アロケータ、ヒープ領域管理、コレクタ実装
- [ ] [ulisp/passes/04_codegen.scm](file:///workspace/arxiv-security-papers/ulisp/passes/04_codegen.scm): GC セーフポイント、スタックルート追跡規約
- [ ] [ulisp/test.sh](file:///workspace/arxiv-security-papers/ulisp/test.sh): 大規模アロケーション耐久テストの追加
- [ ] [ulisp/bootstrap.sh](file:///workspace/arxiv-security-papers/ulisp/bootstrap.sh): セルフホスティング不動点検証
- [ ] [docs/issues/README.md](file:///workspace/arxiv-security-papers/docs/issues/README.md): Issue 台帳の更新

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/501-implement-ulisp-target-garbage-collector`

1. **2空間ヒープの確保**:
   - `from-space` と `to-space` のデュアルヒープメモリ管理。
2. **スタックルート走査**:
   - `rsp` からベースポインタまでのスタックフレームを走査し、Tagged Pointer をルートとして特定。
3. **オブジェクト退避とフォワーディングポインタ**:
   - 活性オブジェクトを `to-space` へコピーし、元のヘッダにフォワーディングポインタを残して参照を更新。
4. **耐久テストとセルフホスト検証**:
   - 少ないメモリ（例: 8MB）で大量のペアを生成するテストで GC 発動を確認。
   - 3段階ブートストラップの不動点を検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] GC が発動し、限られたヒープサイズで大量のアロケーションを行ってもクラッシュせず完走すること。
- [ ] `ulisp/test.sh` の全テストが 100% PASS すること。
- [ ] `ulisp/bootstrap.sh` の不動点検証（`diff stage2.s stage3.s == 0`）が成立すること。
- [ ] すべての品質ゲート（`make check_format`, `make static_analysis`）を通過すること。

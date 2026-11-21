# Issue #910: ULisp ブートストラップシードドリフトの解消および Pass Manager 大域脱出復元の修正

## 1. 概要 (Overview)
- **課題**:
  - `make -C ulisp bootstrap` および `make -C ulisp build/ulisp-modular` を実行した際、`build/ulisp_stdlib.s` のコンパイル時に `[LIR COMPILER ERROR] Unbound Variable Resolution Failed: sys-initial-heap` が発生してビルドが停止していた。
  - Issue #905 で導入された Demand-Paged BSS ヒーププリミティブ（`sys-initial-heap`）がシードバイナリ（`ulisp/bin/ulisp-boot`）に含まれていなかったため、標準ライブラリ（`ulisp/lib/posix.scm`）のコンパイル時に未束縛変数と判定されていた。
  - さらに、ホスト Scheme（Gauche）でのエラー表示シム欠落（`unbound variable: port-read-line`）および `test_pass_manager` のテスト 10.21 における大域脱出時（`call/cc` / `raise`）のピコパス無効化状態復元漏れが存在していた。
- **目的**:
  - ホスト環境用シムを追加し、最新のコンパイラコードで `build/ulisp-modular` をリビルドして `bin/ulisp-boot` を昇格。
  - `auto-bisect-picopasses` に `dynamic-wind` を適用し、例外や大域脱出時にも確実に状態が復元されるように修正。
  - `make -C ulisp bootstrap`、`make -C ulisp build/ulisp-modular`、および `make -C ulisp test` の全テストスイートの 100% PASS を達成する。

---

## 2. 変更内容 (Changes)
1. **ホスト環境互換シムの追加 (`ulisp/compiler/helpers.scm`)**:
   - Gauche 実行環境でのエラーレポート・診断出力に必要な `(define (port-read-line p) (read-line p))` を追加。
2. **ピコパス自動バイセクト状態復元の堅牢化 (`ulisp/compiler/pass_manager.scm`)**:
   - `auto-bisect-picopasses` の `reset-disabled-picopasses!` と `set-car! *disabled-picopasses* saved-disabled` を `dynamic-wind` でラップし、例外や大域脱出時にも確実に初期状態へ復元されるよう修正。
3. **ブートストラップシードバイナリの昇格 (`ulisp/bin/ulisp-boot`)**:
   - `sys-initial-heap` プリミティブを完全に認識する最新のコンパイラコードを用いてモジュラーバイナリをビルドし、3-Stage Fixed-Point Verification（bit-for-bit IDENTICAL）により `bin/ulisp-boot` を更新。

---

## 3. 検証結果 (Verification)
- `make -C ulisp build/ulisp-modular`: エラー 0 件で正常完了。
- `make -C ulisp bootstrap`: Stage 2 と Stage 3 の全 5 モジュール出力が bit-for-bit IDENTICAL で一致、Smoke Test (42) PASS。
- `make -C ulisp test`: 全 Nanopass 単体テスト（786件）、Pass Manager 統合テスト（126件）、PEG コンパイラ、CI 並行ハーネス（13,600件）、ELF 再配置、差分ファジング、SRFI ライブラリ群、GC ストレス耐性テストすべて PASS。
- `make py_compile && make static_analysis`: 全 617 ファイルに対して構文・静的解析エラー 0 件。

---

## 4. Definition of Done (DoD)
- [x] `make -C ulisp build/ulisp-modular` がエラーなく成功すること
- [x] `make -C ulisp bootstrap` が bit-for-bit IDENTICAL で完遂すること
- [x] `make -C ulisp test` の全テストが PASS すること
- [x] 相対パス規則を厳守していること

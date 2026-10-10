---
ID: 508
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT/ENH] MLisp の AOT 統合および JIT 内蔵型ワンバイナリ (scheme-jit) の生成 (ID: 508)

## 1. 概要 / Summary
Pure Scheme による内因的メタトレーシング JIT フレームワーク（MLisp）を、ULisp の自己ホスティング AOT コンパイラ（Pass 0〜7）と完全統合する。
RPython において PyPy インタプリタと JIT 生成器を単一の実行可能バイナリ（`pypy-c`）へと事前コンパイル（AOT）するのと同様に、ULisp コンパイラ自身および MLisp ツールチェーン（限定継続、トレーサ、オプティマイザ、LIR ブリッジ、JIT メモリバッファ）を ULisp AOT コンパイラによって丸ごとコンパイルし、**「実行時メタトレース JIT を内蔵した単一自己完結バイナリ（`bin/scheme-jit`）」** を生成可能とする。

---

## 2. トレーサビリティ / Traceability
- 関連設計書: [DSN-34: MLisp 内因的メタトレーシング JIT アーキテクチャ仕様書 §5.1 ビルド時パイプライン (Pure Scheme JIT VM)](../designs/DSN-34-mlisp_endogenous_meta_tracing_jit_architecture_specification.md)
- 関連 Issue: [Issue 507: 限定継続と ULisp LIR に基づく内因的メタトレーシング JIT ツールチェーン (MLisp) の実装](closed/507-implement-mlisp-endogenous-meta-tracing-jit.md)
- 関連 Issue: [Issue 493: ULisp Phase 7 セルフホスティングブートストラップ連鎖と不動点検証](closed/493-implement-ulisp-phase7-self-hosting-bootstrap-and-fixed-point.md)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [mlisp/core/delimcc.scm](../../mlisp/core/delimcc.scm) (AOT 適合化: レスト引数解消、クロージャ変換対応)
- [ ] [mlisp/tracer/tracer.scm](../../mlisp/tracer/tracer.scm) (AOT 適合化: 状態表現とリスト引数純化)
- [ ] [mlisp/optimizer/pe.scm](../../mlisp/optimizer/pe.scm) (AOT 適合化)
- [ ] [mlisp/optimizer/virtuals.scm](../../mlisp/optimizer/virtuals.scm) (AOT 適合化)
- [ ] [mlisp/bridge/to_lir.scm](../../mlisp/bridge/to_lir.scm) (ULisp LIR 生成ブリッジの AOT 結合)
- [ ] [mlisp/runtime/jit_buffer.scm](../../mlisp/runtime/jit_buffer.scm) (mmap/mprotect/sys-call インターフェースの C ランタイム結合)
- [ ] [mlisp/driver/scheme_jit.scm](../../mlisp/driver/scheme_jit.scm) (AOT ビルド用メインエントリポイント)
- [ ] [ulisp/runtime.c](../../ulisp/runtime.c) (JIT 実行可能メモリバッファ用補助プリミティブの必要性確認)
- [ ] [mlisp/Makefile](../../mlisp/Makefile) (`scheme-jit` ターゲット追加)
- [ ] [mlisp/README.md](../../mlisp/README.md) (ビルドと実行手順の更新)

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/508-integrate-mlisp-with-ulisp-aot-compiler`

1. **MLisp モジュール群の AOT コンパイラ構文制約への適合化**:
   - ULisp AOT コンパイラ（Pass 1〜7）における制約（ドット対レスト引数 `(lambda (x . rest))` の未サポート対応、トップレベルスコープの `rewrite-top-level` への適合）を解消し、純粋なリスト構文および明示的リスト引数渡しにリファクタリング。
2. **JIT メモリ実行インターフェースの AOT 結合**:
   - `runtime/jit_buffer.scm` における機械語バッファ確保と呼び出し（関数ポインタ呼び出し）を、ULisp ランタイム（`ulisp/runtime.c`）と直接連携できるように整備。
3. **`scheme-jit` 統合メインドライバの作成**:
   - ULisp のフロントエンド／評価器および MLisp のメタトレーサ・JIT コンパイラを結合する `mlisp/driver/scheme_jit.scm` を実装。
4. **Makefile ビルドターゲットの整備**:
   - `ulisp/build/scheme-stage2` を用いて Scheme ソースを一括して x86-64 アセンブリ（`.s`）へコンパイルし、GCC でリンクして `mlisp/bin/scheme-jit` を生成するターゲットを追加。
5. **自己完結動作の検証**:
   - 生成された `scheme-jit` 単一バイナリ上で、インタプリタ実行およびループ検出による JIT トレース・最適化・マシンコード直接実行が正常に動作することを検証。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] MLisp の各コアモジュール（delimcc, tracer, optimizer, to_lir, jit_buffer）が ULisp AOT コンパイラでエラーなくアセンブリ生成されること
- [ ] `make -C mlisp scheme-jit`（または `bin/scheme-jit`）により単一のネイティブ ELF バイナリが正常に生成されること
- [ ] 生成された `scheme-jit` バイナリが Python 非依存でスタンドアロン動作し、Scheme プログラムの評価およびメタトレース JIT 高速化を行えること
- [ ] 既存のテストスイート（`make -C mlisp test` および `make check`）がすべて 100% PASS すること

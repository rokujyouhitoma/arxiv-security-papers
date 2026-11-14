---
ID: 834
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] 純粋 Scheme 製 LIR 参照インタプリタ (Reference VM) の実装 (ID: 834)

## 1. 概要 / Summary
x86_64 バックエンド（140）や C バックエンド（160）などのネイティブコード生成器に依存せず、低レベル中間表現（LIR）の命令シーケンスを直接ステップ実行・検証できる純粋 Scheme 製の参照仮想マシン（LIR Reference VM: `ulisp/vm/lir_interpreter.scm`）を実装する。
これにより、ネイティブアセンブラやリンカの完成を待つことなく、C フロントエンドからの Lowering や各種 LIR 最適化パス（SSA、ピープホール）の正当性をミリ秒単位でデバッグ・検証できるようにし、開発のフィードバックループを劇的に高速化する。また将来の Scheme インタプリタ用バイトコード VM の参照モデルとしても機能させる。

---

## 2. トレーサビリティ / Traceability
- **DSN-38**: §2 (K3: LIR レベル差分テスト, §4: 未決事項 4), S1/S2 検証基盤
- **関連 Issue**: #826 (Typed LIR), #828 (Overflow Arithmetic), #831 (C Backend Sync)

---

## 3. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [ulisp/vm/lir_interpreter.scm](../../ulisp/vm/lir_interpreter.scm): LIR 命令列の仮想マシン評価器（仮想レジスタ・スタック・メモリモデル）
- [ ] [ulisp/compiler/lir.scm](../../ulisp/compiler/lir.scm): LIR ノードの命令デコードインターフェース
- [ ] [ulisp/tests/test_lir_interpreter.scm](../../ulisp/tests/test_lir_interpreter.scm): 参照 VM による算術・メモリ・分岐実行テスト

---

## 4. 実装方針 / Implementation Plan
Target Branch: `feat/834-pure-scheme-lir-reference-vm`

1. 仮想実行状態（VM State）の定義：
   - 仮想レジスタファイル（`vector` または環境連想テーブル）。
   - シミュレートされたリニアメモリ（`bytevector` による 64MB 仮想空間、8/16/32/64bit ロード・ストア）。
   - コールスタックおよびプログラムカウンタ（ブロックラベル + 命令インデックス）。
2. 命令ディスパッチの実装：
   - 基本ブロック遷移、条件ジャンプ、整数/浮動小数点算術命令（Issue #826, #828 準拠）。
   - 関数呼び出し（`%call`）およびスタックフレーム管理。
3. デバッグ・トレーシング機構：
   - ステップごとのレジスタ変更差分およびメモリアクセスログ出力フック。

---

## 5. 完了条件 / Success Criteria (DoD)
- [ ] 参照 VM 上で、多分岐・ループ・関数呼出し・メモリポインタ演算を含む LIR スクリプトが正しくステップ実行され、期待通りの戻り値が得られること。
- [ ] 単体テスト `test_lir_interpreter.scm` が全項目合格すること。
- [ ] x86 ネイティブバイナリと参照 VM の実行結果を直接比較するアサーションが成立すること。

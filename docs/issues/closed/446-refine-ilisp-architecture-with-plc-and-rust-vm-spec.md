---
ID: 446
種別: Feature
優先度: High
ステータス: Open (New)
---

# [FEAT] ILISP 包括アーキテクチャ設計 (DSN-31) および ilisp/docs の PLC 処理系工学・Rust VM ロードマップ反映 (ID: 446)

## 1. 概要 / Summary
プログラミング言語・コンパイラ処理系スペシャリスト（PLC）による言語処理系工学的精査に基づき、ILISP (Intelligence LISP) の包括設計仕様書（DSN-31）および言語ドキュメント体系（ilisp/docs/）を改定する。
具体的には、Scope Sets マクロ展開、ハイブリッド TCO（自己末尾ループ化＋相互呼出トランポリン）、階層的 call/cc（Python: 脱出継続 / C99: 完全継続）、Python 例外の現場復帰ラッパー（Boundary Guard）、Zero-Copy Lazy View、セルフホスト用 Kernel ILISP 仕様、および C99 AOT に加えた「将来の Rust バイトコード VM（No-GIL並行性 / NaN-Boxing / PyO3連携）」の 3 本柱アーキテクチャを明文化・統合する。

---

## 2. 影響範囲と関連ファイル / Scope and Affected Files
- [ ] [docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md](../designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md)
- [ ] [ilisp/docs/SPEC_R7RS.md](../../ilisp/docs/SPEC_R7RS.md)
- [ ] [ilisp/docs/BOOTSTRAP.md](../../ilisp/docs/BOOTSTRAP.md)
- [ ] [ilisp/docs/README.md](../../ilisp/docs/README.md)
- [ ] [docs/issues/README.md](README.md)

---

## 3. 実装方針 / Implementation Plan
Target Branch: `feat/446-refine-ilisp-architecture-with-plc-and-rust-vm-spec`

1. **DSN-31 の改定**:
   - 実行バックエンドの 3 本柱構成（Python AST, C99 AOT / Clang LLVM, Rust Bytecode VM）の明記。
   - Scope Sets マクロ展開モデルとフェーズ分離規定の追記。
   - ハイブリッド TCO（ループ化＋軽量トランポリン）の技術仕様追加。
   - 階層的 call/cc（One-shot 脱出継続 vs C99 Full Continuation）の定義。
   - Python 境界ラッパー（Boundary Guard）によるコンディション回復機構。
   - Zero-Copy Lazy View（Opaque Object Wrapper）による $O(1)$ Python Interop。
   - セルフホスティング用 `Kernel ILISP` 仕様の追記。
2. **ilisp/docs/ の同期**:
   - `ilisp/docs/SPEC_R7RS.md`: マクロ、TCO、call/cc、拡張ライブラリ仕様の更新。
   - `ilisp/docs/BOOTSTRAP.md`: Kernel ILISP サブセット定義と段階的セルフホスト手順の拡充。
   - `ilisp/docs/README.md`: 3 本柱バックエンドおよび最新アーキテクチャ概要の更新。
3. **品質検証**:
   - 相対パスリンクガバナンスの検証。
   - `make check_format` および `make static_analysis` の完全合格。

---

## 4. 完了条件 / Success Criteria (DoD)
- [x] DSN-31 に PLC 7大設計改善項目および Rust VM ロードマップが詳細に明文化されていること
- [x] `ilisp/docs/SPEC_R7RS.md` に Scope Sets, ハイブリッドTCO, 階層的call/cc, Zero-Copy View が反映されていること
- [x] `ilisp/docs/BOOTSTRAP.md` に Kernel ILISP 最小仕様が定義されていること
- [x] `ilisp/docs/README.md` に 3本柱バックエンド構想が反映されていること
- [x] リポジトリ内の絶対パスリンクが 0 件であること
- [x] `make check_format` および `make static_analysis` が 100% PASS すること

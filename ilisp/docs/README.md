# ILISP (Intelligence LISP)

> **Next-Generation AI-Native Lisp Dialect adhering to R7RS-small Scheme with Dual Python-Interop and Native C-AOT Backends.**

ILISP (Intelligence LISP) は、知性・脅威インテリジェンス（Intelligence）、創設者の哲学（IKE）、そして人工知能（AI）を象徴するモダンな Lisp 方言です。

世界標準規格 **R7RS-small Scheme** を中核仕様として採用し、Python の広大な AI/NLP エコシステムと摩擦ゼロで双方向連携できる **Python-Interop モード** と、GIL フリーでミリ秒起動・単一バイナリ配布を可能にする **Native C-AOT モード** を兼ね備えています。

---

## 主な特徴 (Key Highlights)

1. **R7RS-small Scheme 世界標準準拠**:
   - `define-library` によるモジュール管理、数学的に安全な衛生的マクロ (`syntax-rules`)、末尾呼び出し最適化 (TCO)、ファーストクラスの継続 (`call/cc`) を完備。
2. **摩擦ゼロの Python 相互運用 (Zero-Friction Interop)**:
   - ILISP から PyPI の全ライブラリ（`torch`, `transformers`, `arxiv` 等）を透過的に直接インポート・呼び出し可能。
   - Python からも通常通り `import my_ilisp_module` として ILISP コードをシームレスに利用可能。
3. **Native C-AOT コンパイル (Chicken Scheme / Nim 方式)**:
   - ILISP コードからクリーンな C99 ソースコードを生成し、`gcc` / `clang` で最適化された高速単一実行バイナリを出力。
4. **現場復帰型コンディションシステム (Conditions & Restarts)**:
   - スタックを巻き戻さずに例外発生現場で回復手段（リトライ、RSSフォールバック等）を上位から注入可能。
5. **完全セルフホスティング（Bootstrap Chain）対応**:
   - Stage-0 (Python host) から Stage-2 への自己完結ブートストラップ連鎖と不動点検証を設計レベルでビルトイン。

---

## クイックスタート (Quickstart Preview)

### 基本的な式と Python Interop
```scheme
;; (scheme base) と Python 相互運用ライブラリの利用
(import (scheme base)
        (scheme write)
        (ilisp python))

;; Python モジュールのインポート
(import-python (math sqrt)
               (pathlib Path))

;; 関数定義とスレッディングマクロ
(define (analyze-numbers lst)
  (|>> lst
       (filter (lambda (x) (> x 0)))
       (map (lambda (x) (py-call sqrt x)))))

(display (analyze-numbers '(-4 9 -1 16 25)))
;; => (3.0 4.0 5.0)
```

---

## ドキュメント体系

- [SPEC_R7RS.md](SPEC_R7RS.md): R7RS-small 仕様準拠マトリクス・サポート状況
- [BOOTSTRAP.md](BOOTSTRAP.md): 3段階セルフホスティング・ブートストラップ連鎖仕様
- [DSN-31 包括設計仕様書](../../docs/designs/DSN-31-ilisp_r7rs_intelligence_lisp_architecture_specification.md): アーキテクチャ包括設計書

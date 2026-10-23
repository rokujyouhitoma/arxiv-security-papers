# ULisp ファーストクラス継続 (`call/cc`) & `dynamic-wind` 詳細技術仕様書

本ドキュメントは、ULisp (Underlying LISP) における **R7RS Section 6.10 (Control features)** 準拠のファーストクラス継続 (`call/cc`, `call-with-current-continuation`) およびスタック出入り保護機構 (`dynamic-wind`) のアーキテクチャ、内部データ構造、スタックコピー方式、および LCA (Lowest Common Ancestor) アンワインド/リワインドアルゴリズムを定義する。

- 関連仕様書: [DSN-33 (ULisp 包括設計仕様書)](../../docs/designs/DSN-33-ulisp_underlying_x86_native_aot_compiler_architecture_specification.md)
- 実装モジュール:
  - 高水準ライブラリ: [ulisp/lib/continuation.scm](../lib/continuation.scm)
  - 中間表現パス: [ulisp/lir/125_lir_continuation.scm](../lir/125_lir_continuation.scm), [ulisp/lir/130_lir.scm](../lir/130_lir.scm)
  - ネイティブバックエンド: [ulisp/backend/140_backend_x86_64.scm](../backend/140_backend_x86_64.scm), [ulisp/backend/160_backend_c.scm](../backend/160_backend_c.scm), [ulisp/backend/150_backend_aarch64.scm](../backend/150_backend_aarch64.scm)
  - テストスイート: [ulisp/tests/test_call_cc.scm](../tests/test_call_cc.scm)

---

## 1. 概要とアーキテクチャ設計原則

ULisp はコンパイル時にスタックベースのネイティブ実行モデル（x86-64 System V AMD64 ABI 準拠）を採用している。完全なファーストクラス継続（Multi-shot Reentrant Continuations）をサポートするため、**スタックセグメントコピー（Stack-Segment Copying）方式** を採用している。

```text
┌─────────────────────────────────────────────────────────────┐
│ (call/cc (lambda (k) ... (k val) ...))                     │
└──────────────┬──────────────────────────────▲───────────────┘
               │                              │
     1. %capture-cc (退避)             3. continuation-invoke (復元)
               ▼                              │
┌──────────────────────────────┐              │
│ Heap Continuation Closure    │──────────────┘
│ ┌──────────────────────────┐ │
│ │ Tag: 0x01 (Closure)      │ │
│ │ Target RIP (復帰ラベル)  │ │
│ │ Target RSP (復帰スタック)│ │
│ │ Stack Size (バイト数)    │ │
│ │ Stack Data (退避配列)    │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

### 設計原則
1. **完全な Multi-shot 複数回復帰の保証**:
   エスケープ脱出（1回限りの大域脱出）だけでなく、過去に取得した継続オブジェクト `(k val)` を何度でも再突入実行可能。
2. **決定論的リワインドと dynamic-wind 整合性**:
   継続ジャンプ時にアクティブな `dynamic-wind` 境界を跨ぐ場合、LCA（最小共通祖先）を算出して外側への `after` 実行（unwind）と内側への `before` 実行（rewind）を厳密な順序で呼び出す。
3. **境界防壁（Clamp Guard）**:
   スタック長計算時の境界不整合によるオーバーフローを防止するため、8MB の安全上限クランプガードを適用。
4. **多値（Multiple Values / Issue #538）とのシームレスな統合**:
   `(call/cc (lambda (k) (k (values 1 2 3))))` を受け取り側 `call-with-values` へ無損失で引き渡す。

---

## 2. 継続オブジェクトの内部表現 (Data Layout)

ULisp における継続オブジェクトは、通常のクロージャ（タグ `0x01`）と同一のヘッダ構造を持ち、第 1 引数に関数エントリポイント（`ulisp_continuation_invoke` ラベル）を保持する。

```text
継続オブジェクト (Closure Tuple in Heap):
[Header: Type=0x01, Size=6 words]
 Word 0: [Code Pointer] -> ulisp_continuation_invoke へのアドレス
 Word 1: [Target RIP]   -> %capture-cc 呼び出し直後の復帰ラベル (.Lcc_ret_XXXX)
 Word 2: [Target RSP]   -> キャプチャ時点のスタックポインタ
 Word 3: [Stack Bytes]  -> 退避スタック長 (Fixnum エンコード)
 Word 4: [Heap Ptr]     -> 退避されたスタックバイト列のヒープアドレス
 Word 5: [Exn Chain]    -> キャプチャ時点の例外ハンドラチェーン
```

- **Tag**: 下位 3 ビットが `001` (Closure)。
- **呼び出し透過性**: Scheme コードからは通常の 1 引数関数 `(k val)` として呼び出し可能（`Pass 5: closure-convert` で通常の関数適用として処理される）。

---

## 3. x86-64 ネイティブバックエンドの動作メカニズム

### 3.1 スタック底（`ulisp_stack_base`）の初期化
プログラム起動時（`scheme_entry:`）に、最上位フレームのベースポインタを BSS セクションの `ulisp_stack_base` に記録する。

```assembly
.globl scheme_entry
scheme_entry:
    movq %rsp, ulisp_stack_base(%rip)
    ...
```

### 3.2 `%capture-cc` (継続のキャプチャ)
`%raw-call/cc` が呼び出されると、以下の手順で現在の実行コンテキストを退避する。

1. **スタック長計算**:
   `ulisp_stack_base - %rsp` を計算し、現在の有効なスタック領域サイズを算出。負数チェックおよび 8MB 安全上限クランプを行う。
2. **スタックバイト列のヒープ割当**:
   バンプアロケータ（`%r12`）を用いてスタックデータをヒープへ全複写（`rep movsb`）。
3. **自己継続クロージャの生成とスタック更新**:
   継続オブジェクトを作成し、スタック複写領域内の該当スロットに格納（再突入時に自己参照が正しく得られるようにする）。
4. **レシーバ呼び出し**:
   作成された継続オブジェクトを引数として、レシーバ関数 `(lambda (raw-k) ...)` を呼び出す。
5. **復帰アンカーラベル（`.Lcc_ret_XXXX`）の配置**:
   通常復帰または後述の `ulisp_continuation_invoke` からの再突入を受け止める合流ラベルを配置。

### 3.3 `ulisp_continuation_invoke` (継続の復元と再突入)
継続オブジェクトが呼び出されると、`ulisp_continuation_invoke` へジャンプする。

1. **引数レジスタの保護**:
   渡された引数値（戻り値 `val`）を `%rdi` に一時退避。
2. **スタックの再配置と復元**:
   継続オブジェクトから `Target RSP`、`Stack Bytes`、`Heap Ptr` を読み出し、`%rsp` を `Target RSP` に巻き戻してヒープからスタックへデータを書き戻す（`rep movsb`）。
3. **レジスタ・例外チェーンの復元**:
   例外ハンドラチェーン `ulisp_exn_handler` をキャプチャ時点の状態へリセット。
4. **戻り値の設定とジャンプ**:
   `%rax` に戻り値 `val` をセットし、`Target RIP` へ直接ジャンプ（`jmp *%rax`）。

---

## 4. `dynamic-wind` と LCA 共通祖先アンワインド/リワインド

`ulisp/lib/continuation.scm` は、大域セル `*ulisp-wind-cell*` を通じて現在アクティブな `(before . after)` フレームのリスト（`wind-chain`）を追跡する。

### 4.1 LCA 探索とチェーン遷移アルゴリズム (`wind-to`)

継続ジャンプ先がキャプチャされた時の `captured-wind` と、現在のジャンプ元の `current-wind` が異なる場合、`wind-to` 手続きが起動される。

```text
       [Root Chain: '()]
             ▲
             │
         [Frame 1]  <-- LCA (Lowest Common Ancestor)
        /         \
   [Frame 2A]    [Frame 2B]
      /               \
[Current State]  [Target State]
```

1. **深さ測定**:
   `current-wind` と `target-wind` のチェイン長を測定する。
2. **浅い側への unwind**:
   `current` の方が深い場合、`current` のチェインをポップしながら各フレームの `after` 手続きを呼び出す。
3. **LCA の探索**:
   両者の深さが揃ったら、ポインタ等値（`eq?`）になるまで両チェインを親方向へステップアップ。その際、`current` 側は `after` を呼び出し、`target` 側は巻き戻し対象（`to-rewind`）スタックへ蓄積する。
4. **ターゲット側への rewind**:
   LCA に到達したら、`to-rewind` スタックをポップしながらターゲットフレームの `before` 手続きを呼び出し、`*ulisp-wind-cell*` をターゲット状態へ遷移させる。

---

## 5. ユースケースと動作検証

### 5.1 単純エスケープ脱出
```scheme
(call/cc (lambda (k) (+ 1 (k 41)))) ; => 41 (+ 1 ...) は実行されずに脱出
```

### 5.2 Multi-shot 複数回復帰
```scheme
(let* ((saved-k-box (make-box #f))
       (val (call/cc (lambda (k) (box-set! saved-k-box k) 10))))
  (cond
    ((= val 10) ((box-ref saved-k-box) 100))
    ((= val 100) ((box-ref saved-k-box) 200))
    ((= val 200) val))) ; => 200
```

### 5.3 協調型コルーチン（Coroutine Generator）
```scheme
(define (make-generator)
  (let* ((yield-k-box (make-box #f))
         (return-k-box (make-box #f)))
    (lambda ()
      (call/cc (lambda (k)
                 (box-set! return-k-box k)
                 (let ((yk (box-ref yield-k-box)))
                   (if yk
                       (yk #t)
                       (let loop ((i 10))
                         (call/cc (lambda (new-yk)
                                    (box-set! yield-k-box new-yk)
                                    ((box-ref return-k-box) i)))
                         (loop (+ i 10))))))))))
```

---

## 6. テスト実行と品質保証

本機能は `ulisp/tests/test_call_cc.scm` によって以下の 7 つのシナリオが自動テストされ、すべて PASS することが保証されている。

```bash
# call/cc 単体テストの実行
make -C ulisp test_call_cc

# 出力例
=== Running ULisp First-Class call/cc & dynamic-wind Tests ===
--- Test 1: Simple Escape Continuation ---
  [PASS] call/cc escape aborts pending addition
  [PASS] call/cc normal return without invocation
  [PASS] call/cc nested in arithmetic expression
--- Test 2: Multi-shot Reentrancy ---
  [PASS] first run returns 10
  [PASS] re-entry with 100 returns 100
  [PASS] second re-entry with 200 returns 200
--- Test 3: dynamic-wind Basic Evaluation ---
  [PASS] dynamic-wind returns thunk result
  [PASS] before ran first
  [PASS] thunk ran second
  [PASS] after ran third
--- Test 4: dynamic-wind Unwinding on Escape ---
  [PASS] escape returns target value
  [PASS] inner after ran on escape
  [PASS] outer after ran on escape
--- Test 5: dynamic-wind Re-entry Rewinding ---
  [PASS] first run result is 1
  [PASS] re-entry result is 2
  [PASS] log has 6 entries after re-entry
--- Test 6: call/cc with Multiple Values (Issue #538 integration) ---
  [PASS] call/cc passes multiple values to call-with-values
  [PASS] call/cc passes 3 multiple values
--- Test 7: Coroutine Generator ---
  [PASS] coroutine first item is 10
  [PASS] coroutine second item is 20
  [PASS] coroutine third item is 30
  [PASS] coroutine finished
=== All First-Class call/cc & dynamic-wind Tests Complete ===
```

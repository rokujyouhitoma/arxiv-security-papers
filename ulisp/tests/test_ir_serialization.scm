;;; =======================================================================
;;; Unit & Integration Test Suite: IR Serialization & Deserialization (.sbi v2)
;;; Issue #839 - Covers Cryptographic SHA-256, LEB128, CST/HIR/MIR/LIR
;;; Round-Trip, <source-span>/<binding> Metadata, Threat Model Mitigations
;;; (THREAT-839-1..4), Header Checksum Auto-Invalidation, PCH Benchmark (>=5x),
;;; Legacy .sbi v1 Fallback, and LTO Multi-Module Merging.
;;; =======================================================================

(display "=======================================================\n")
(display " Starting IR Serialization (.sbi v2) Suite (#839)\n")
(display "=======================================================\n")

(define *sbi-test-count* (cons 0 '()))
(define *sbi-pass-count* (cons 0 '()))

(define (sbi-print-group title)
  (newline)
  (display title)
  (newline))

(define (sbi-assert-true name val)
  (set-car! *sbi-test-count* (+ (car *sbi-test-count*) 1))
  (if val
      (begin
        (set-car! *sbi-pass-count* (+ (car *sbi-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (sbi-assert-false name val)
  (set-car! *sbi-test-count* (+ (car *sbi-test-count*) 1))
  (if (not val)
      (begin
        (set-car! *sbi-pass-count* (+ (car *sbi-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] Expected #f but got truthy: ")
        (display name)
        (newline)
        (error "Assertion failed" name))))

(define (sbi-assert-equal name expected actual)
  (set-car! *sbi-test-count* (+ (car *sbi-test-count*) 1))
  (if (sbi-equal? expected actual)
      (begin
        (set-car! *sbi-pass-count* (+ (car *sbi-pass-count*) 1))
        (display "  [PASS] ")
        (display name)
        (newline))
      (begin
        (display "  [FAIL] ")
        (display name)
        (display "\n    Expected: ")
        (write expected)
        (display "\n    Actual:   ")
        (write actual)
        (newline)
        (error "Assertion failed" name))))

(define (sbi-test-now-seconds)
  (let ((s1 (guard (ex (else #f)) (current-second))))
    (if (and (number? s1) (> s1 1000000000))
        s1
        (guard (ex (else 0.0))
          (call-with-values sys-gettimeofday
            (lambda (sec usec)
              (+ (* sec 1.0) (/ usec 1000000.0))))))))

(define (sbi-write-text-file path content)
  (let ((p (open-output-file path)))
    (display content p)
    (close-output-port p)))

(define (sbi-read-forms-from-string str)
  (let ((p (open-input-string str)))
    (let loop ((acc '()))
      (let ((f (read p)))
        (if (eof-object? f)
            (begin
              (close-input-port p)
              (reverse acc))
            (loop (cons f acc)))))))

;;; -----------------------------------------------------------------------
;;; Group 1: Cryptographic SHA-256 & Bounded LEB128 Primitives
;;; -----------------------------------------------------------------------
(sbi-print-group "--- Group 1: SHA-256 (FIPS 180-4) & ULEB128/SLEB128 Codecs ---")

(sbi-assert-equal "1.1 SHA-256 empty string matches NIST vector"
                  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                  (sbi-sha256-hex ""))

(sbi-assert-equal "1.2 SHA-256 'abc' matches NIST vector"
                  "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                  (sbi-sha256-hex "abc"))

(sbi-assert-equal "1.3 SHA-256 multi-block message matches NIST vector"
                  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
                  (sbi-sha256-hex "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))

(let ((uleb-cases '(0 1 127 128 16383 16384 65535 16777215 2147483647 1099511627776)))
  (for-each
    (lambda (v)
      (let* ((bv (sbi-write-uleb128 v))
             (dec (sbi-read-uleb128 bv 0)))
        (sbi-assert-equal "1.4 ULEB128 round-trip" v (car dec))))
    uleb-cases))

(let ((sleb-cases '(0 1 -1 63 -64 64 -65 127 -128 32767 -32768 2147483647 -2147483648 -1099511627776)))
  (for-each
    (lambda (v)
      (let* ((bv (sbi-write-sleb128 v))
             (dec (sbi-read-sleb128 bv 0)))
        (sbi-assert-equal "1.5 SLEB128 round-trip" v (car dec))))
    sleb-cases))

;;; -----------------------------------------------------------------------
;;; Group 2: Multi-Stage IR, Metadata & Reference LIR VM Execution Parity
;;; -----------------------------------------------------------------------
(sbi-print-group "--- Group 2: CST/HIR/MIR/LIR, <source-span>, <binding> & VM Parity ---")

;; 2.1 Atoms, dotted pairs, vectors, bytevectors, flonums, UTF-8 strings
(let* ((bv-sample (let ((b (make-bytevector 4 0)))
                    (bytevector-u8-set! b 0 11)
                    (bytevector-u8-set! b 1 22)
                    (bytevector-u8-set! b 2 33)
                    (bytevector-u8-set! b 3 44)
                    b))
       (span1 (make-source-span "src/demo.scm" 12 4 12 28 #f 101))
       (span2 (make-source-span "src/macro.scm" 3 1 3 19 span1 102))
       (bnd1 (make-binding 7 'acc 'acc_g7 'variable 'ordinary 3
                           'auto '(fixnum exact) 'local '(1 3 5) span2))
       (complex-datum
         (list 'envelope
               '()
               #t #f
               0 -1 42 123456789012345
               123456789012345678901234567890
               3.14159
               #\Z
               "ASCII & 日本語 UTF-8"
               (cons 'dotted-head 'dotted-tail)
               (vector 'vec-elem span2 bnd1 bv-sample)))
       (ser (sbi-serialize complex-datum 'cst))
       (de (sbi-deserialize ser)))
  (sbi-assert-true "2.1a Serialized buffer has USBI v2 header" (sbi-binary-bytevector? ser))
  (sbi-assert-true "2.1b Complex Scheme + Unicode + dotted + <source-span> + <binding> round-trips 100%"
                   (sbi-equal? complex-datum de))
  (let* ((vec (list-ref de 13))
         (de-span (vector-ref vec 1))
         (de-bnd (vector-ref vec 2)))
    (sbi-assert-true "2.1c Standard equal? also confirms vector/span equality"
                     (equal? (vector 'vec-elem span2 bnd1)
                             (vector 'vec-elem de-span de-bnd)))
    (sbi-assert-true "2.1d Deserialized span satisfies source-span?" (source-span? de-span))
    (sbi-assert-equal "2.1e Deserialized span preserves node-id" 102 (span-node-id de-span))
    (sbi-assert-true "2.1f Deserialized span preserves nested macro-origin span"
                     (source-span? (span-macro-origin de-span)))
    (sbi-assert-true "2.1g Deserialized binding satisfies binding?" (binding? de-bnd))
    (sbi-assert-equal "2.1h Deserialized binding preserves unique-sym" 'acc_g7 (binding-unique-sym de-bnd))
    (sbi-assert-equal "2.1i Deserialized binding preserves scope-set" '(1 3 5) (binding-scope-set de-bnd))
    (sbi-assert-equal "2.1j Deserialized binding preserves storage-class" 'auto (binding-storage-class de-bnd))))

;; 2.2 DAG node deduplication (hash-consing)
(let* ((shared-subtree '(%add %rax (%imm 1) (%call $helper (%reg %rdi))))
       (replicated (list shared-subtree shared-subtree shared-subtree
                         shared-subtree shared-subtree shared-subtree
                         shared-subtree shared-subtree))
       (meta (sbi-deserialize-full (sbi-serialize replicated 'lir)))
       (node-count (cdr (assq 'node-count meta))))
  (sbi-assert-true "2.2 DAG deduplication keeps shared subtrees compact (< 25 nodes for 8 copies)"
                   (< node-count 25)))

;; 2.3 Full Frontend -> HIR -> MIR -> Typed LIR Pipeline Round-Trip + LIR VM Parity
(let* ((src-forms '((define (fact n)
                      (if (<= n 1)
                          1
                          (* n (fact (- n 1)))))
                    (define (sum-sq a b)
                      (+ (* a a) (* b b)))
                    (+ (fact 5) (sum-sq 3 4))))
       ;; Capture intermediate stages through real compiler passes
       (cst-forms (map (lambda (f) (list '%source-span
                                         (make-source-span "test_prog.scm" 1 1 5 10 #f 1)
                                         f))
                       src-forms))
       (hir-core (desugar-all (rewrite-top-level (expand-macros-in-forms src-forms))))
       (mir-anf (anf-all hir-core))
       (mir-lifted (closure-convert mir-anf))
       (lir-prog (begin
                   (disable-pass! 'pass-synapse-inject-safepoints)
                   (run-pass-pipeline src-forms #f #f)))
       (vm-src-forms '((define (dbl x) (+ x x))
                       (+ (dbl 15) 12)))
       (vm-lir-prog (run-pass-pipeline vm-src-forms #f #f))
       ;; Serialize & deserialize every IR stage
       (cst-rt (sbi-deserialize (sbi-serialize cst-forms 'cst)))
       (hir-rt (sbi-deserialize (sbi-serialize hir-core 'hir)))
       (mir-anf-rt (sbi-deserialize (sbi-serialize mir-anf 'mir)))
       (mir-lift-rt (sbi-deserialize (sbi-serialize mir-lifted 'mir)))
       (lir-path "build/tmp_sbi_fact.sbi")
       (vm-lir-path "build/tmp_sbi_vm_prog.sbi"))
  (sbi-assert-true "2.3a CST round-trip equal" (sbi-equal? cst-forms cst-rt))
  (sbi-assert-true "2.3b HIR (L_core) round-trip equal" (sbi-equal? hir-core hir-rt))
  (sbi-assert-true "2.3c MIR (L_anf) round-trip equal" (sbi-equal? mir-anf mir-anf-rt))
  (sbi-assert-true "2.3d MIR (L_lifted) round-trip equal" (sbi-equal? mir-lifted mir-lift-rt))
  (sbi-write-file lir-path lir-prog 'lir)
  (sbi-write-file vm-lir-path vm-lir-prog 'lir)
  (let ((lir-rt (sbi-read-file lir-path))
        (vm-lir-rt (sbi-read-file vm-lir-path))
        (cap-asm (lambda (p)
                   (let ((box (vector '())))
                     (with-emit-line-sink
                       (lambda (ln) (vector-set! box 0 (cons ln (vector-ref box 0))))
                       (lambda () (emit-x86-64 p 'none)))
                     (reverse (vector-ref box 0))))))
    (sbi-assert-true "2.3e Typed LIR (L_lir_canonical) disk round-trip equal"
                     (sbi-equal? lir-prog lir-rt))
    (sbi-assert-true "2.3f x86-64 assembly emitted from deserialized .sbi LIR matches original 100%"
                     (sbi-equal? (cap-asm lir-prog) (cap-asm lir-rt)))
    (sbi-assert-equal "2.3g Original compiled Scheme LIR VM execution = 42"
                      42
                      (eval-lir-program-unboxed vm-lir-prog))
    (sbi-assert-equal "2.3h Deserialized .sbi LIR VM execution matches original (= 42)"
                      (eval-lir-program-unboxed vm-lir-prog)
                      (eval-lir-program-unboxed vm-lir-rt))))

;; 2.4 Typed LIR with %inline-asm node (Issue #838 interop)
(let* ((asm-lir (generate-lir
                  '(%program ()
                     (let ((a 17) (b 25))
                       (%inline-asm "mov %0, %1\nadd %0, %2"
                         (:outputs ((a "=r")))
                         (:inputs ((a "r") (b "r")))
                         (:clobbers ("cc")))))))
       (asm-lir-rt (sbi-deserialize (sbi-serialize asm-lir 'lir))))
  (sbi-assert-true "2.4a %inline-asm LIR program round-trips identically"
                   (sbi-equal? asm-lir asm-lir-rt))
  (sbi-assert-true "2.4b Deserialized %inline-asm LIR passes L_lir_canonical? and validate-lir"
                   (and (L_lir_canonical? asm-lir-rt)
                        (validate-lir asm-lir-rt)))
  (sbi-assert-equal "2.4c Deserialized %inline-asm LIR executes identically on VM (42)"
                    42
                    (eval-lir-program-unboxed asm-lir-rt)))

;;; -----------------------------------------------------------------------
;;; Group 3: Security & Tamper Detection (THREAT-839-1..4)
;;; -----------------------------------------------------------------------
(sbi-print-group "--- Group 3: Security Validations & Tamper Rejection (THREAT-839-1..4) ---")

;; THREAT-839-1: Tampered payload SHA-256 mismatch
(let* ((bv (sbi-serialize '(+ 10 20 30) 'lir))
       (tampered (let* ((n (bytevector-length bv))
                        (c (make-bytevector n 0)))
                   (let loop ((i 0))
                     (if (< i n)
                         (begin
                           (bytevector-u8-set! c i (bytevector-u8-ref bv i))
                           (loop (+ i 1)))))
                   ;; Flip bit inside payload byte (past 56-byte header)
                   (bytevector-u8-set! c (- n 1)
                                       (modulo (+ (bytevector-u8-ref c (- n 1)) 1) 256))
                   c))
       (err (guard (ex (else ex)) (sbi-deserialize tampered))))
  (sbi-assert-true "3.1 Payload 1-bit tampering triggers SHA-256 verification error (THREAT-839-1)"
                   (and (pair? err) (eq? (car err) 'sbi-error))))

;; Invalid magic bytes
(let* ((bad-magic (let ((b (make-bytevector 64 0)))
                    (bytevector-u8-set! b 0 #x58) ; 'X'
                    b))
       (err (guard (ex (else ex)) (sbi-deserialize bad-magic))))
  (sbi-assert-true "3.2 Invalid magic header raises 'sbi-error"
                   (and (pair? err) (eq? (car err) 'sbi-error))))

;; Unsupported version
(let* ((bv (sbi-serialize '(define x 1) 'hir))
       (bad-ver (let* ((n (bytevector-length bv))
                       (c (make-bytevector n 0)))
                  (let loop ((i 0))
                    (if (< i n)
                        (begin
                          (bytevector-u8-set! c i (bytevector-u8-ref bv i))
                          (loop (+ i 1)))))
                  (bytevector-u8-set! c 4 99)
                  c))
       (err (guard (ex (else ex)) (sbi-deserialize bad-ver))))
  (sbi-assert-true "3.3 Unsupported version raises 'sbi-error"
                   (and (pair? err) (eq? (car err) 'sbi-error))))

;; Truncated input
(let* ((short-bv (make-bytevector 12 0))
       (err (guard (ex (else ex)) (sbi-deserialize short-bv))))
  (sbi-assert-true "3.4 Truncated header raises 'sbi-error"
                   (and (pair? err) (eq? (car err) 'sbi-error))))

;; THREAT-839-2: Crafted cyclic / self-referential DAG node (child_idx == node_idx)
;; Header: USBI, v2, kind=4, flags=0, deps=0, syms=0, nodes=1, root=0
;; Payload: TAG_PAIR (#x07) car_idx=0 cdr_idx=0 + valid SHA-256 over that 3-byte payload!
(let* ((payload (let ((p (make-bytevector 3 0)))
                  (bytevector-u8-set! p 0 *sbi-tag-pair*)
                  (bytevector-u8-set! p 1 0) ; child_idx 0 >= node_idx 0 -> cycle!
                  (bytevector-u8-set! p 2 0)
                  p))
       (digest (sbi-sha256-bytevector payload))
       (pkt (make-bytevector (+ *sbi-header-size* 3) 0)))
  (bytevector-u8-set! pkt 0 *sbi-magic-0*)
  (bytevector-u8-set! pkt 1 *sbi-magic-1*)
  (bytevector-u8-set! pkt 2 *sbi-magic-2*)
  (bytevector-u8-set! pkt 3 *sbi-magic-3*)
  (bytevector-u8-set! pkt 4 2)
  (bytevector-u8-set! pkt 6 4)
  (bytevector-u8-set! pkt 16 1) ; node_count = 1
  (let loop ((i 0))
    (if (< i 32)
        (begin
          (bytevector-u8-set! pkt (+ 24 i) (bytevector-u8-ref digest i))
          (loop (+ i 1)))))
  (bytevector-u8-set! pkt 56 *sbi-tag-pair*)
  (bytevector-u8-set! pkt 57 0)
  (bytevector-u8-set! pkt 58 0)
  (let ((err (guard (ex (else ex)) (sbi-deserialize pkt))))
    (sbi-assert-true "3.5 Crafted cyclic DAG node (child_idx >= node_idx) rejected (THREAT-839-2)"
                     (and (pair? err) (eq? (car err) 'sbi-error)))))

;; THREAT-839-4: Dependency path traversal rejection
(let* ((fake-sha (sbi-sha256-string "evil"))
       (err (guard (ex (else ex))
              (sbi-serialize '(+ 1 2) 'pch (list (cons "../../etc/passwd" fake-sha))))))
  (sbi-assert-true "3.6 Path traversal '../' in dependency table rejected (THREAT-839-4)"
                   (and (pair? err) (eq? (car err) 'sbi-error))))

;;; -----------------------------------------------------------------------
;;; Group 4: Header Dependency SHA-256 Cache Validation & Auto-Invalidation
;;; -----------------------------------------------------------------------
(sbi-print-group "--- Group 4: PCH Dependency SHA-256 Validation & Invalidation ---")

(let ((hdr-a "build/tmp_sbi_hdr_a.scm")
      (hdr-b "build/tmp_sbi_hdr_b.scm")
      (pch-file "build/tmp_sbi_pch_cache.sbi")
      (build-calls (cons 0 '())))
  (sbi-write-text-file hdr-a "(define hdr-a-val 100)\n")
  (sbi-write-text-file hdr-b "(define hdr-b-val 200)\n")
  ;; First build -> invokes builder-thunk
  (let ((res1 (sbi-load-or-build-pch
                pch-file
                (list hdr-a hdr-b)
                (lambda ()
                  (set-car! build-calls (+ (car build-calls) 1))
                  '((define hdr-a-val 100) (define hdr-b-val 200))))))
    (sbi-assert-equal "4.1 Initial PCH miss triggers build once" 1 (car build-calls))
    (sbi-assert-true "4.2 sbi-cache-valid? returns #t when dependencies unchanged"
                     (sbi-cache-valid? pch-file))
    ;; Second call -> cache hit! builder-thunk NOT invoked
    (let ((res2 (sbi-load-or-build-pch
                  pch-file
                  (list hdr-a hdr-b)
                  (lambda ()
                    (set-car! build-calls (+ (car build-calls) 1))
                    '((should-not-rebuild))))))
      (sbi-assert-equal "4.3 Second call hits cache without rebuilding" 1 (car build-calls))
      (sbi-assert-true "4.4 Cached PCH datum matches built IR" (sbi-equal? res1 res2)))
    ;; Modify 1 byte in hdr-b!
    (sbi-write-text-file hdr-b "(define hdr-b-val 201)\n")
    (sbi-assert-false "4.5 Modifying dependency file by 1 byte invalidates sbi-cache-valid? (THREAT-839-3)"
                      (sbi-cache-valid? pch-file))
    ;; Third call -> auto-rebuilds & updates cache!
    (let ((res3 (sbi-load-or-build-pch
                  pch-file
                  (list hdr-a hdr-b)
                  (lambda ()
                    (set-car! build-calls (+ (car build-calls) 1))
                    '((define hdr-a-val 100) (define hdr-b-val 201))))))
      (sbi-assert-equal "4.6 Auto-invalidated PCH triggers rebuild on stale dependency" 2 (car build-calls))
      (sbi-assert-equal "4.7 Rebuilt PCH contains updated declaration value 201"
                        201 (caddr (cadr res3)))
      (sbi-assert-true "4.8 sbi-cache-valid? returns #t again after rebuild"
                       (sbi-cache-valid? pch-file)))))

;;; -----------------------------------------------------------------------
;;; Group 5: Large Header PCH Reload Benchmark (>= 5.0x Speedup)
;;; -----------------------------------------------------------------------
(sbi-print-group "--- Group 5: Large-Header PCH Benchmark (>= 5.0x Speedup) ---")

(let* ((large-hdr-path "build/tmp_sbi_large_hdr.scm")
       (large-pch-path "build/tmp_sbi_large_hdr.sbi")
       ;; Generate 40 macro/function/const triples (120 decls + call site)
       ;; where each function expands a header macro before HIR cp0-optimize.
       (hdr-forms
         (let loop ((i 0) (acc '()))
           (if (>= i 40)
               (reverse (cons '(+ HDR_CONST_0 (hdr_fn_0 10 20)) acc))
               (let ((fn-sym (string->symbol (string-append "hdr_fn_" (number->string i))))
                     (const-sym (string->symbol (string-append "HDR_CONST_" (number->string i))))
                     (mac-sym (string->symbol (string-append "hdr-mac-" (number->string i)))))
                 (loop (+ i 1)
                       (cons (list 'define const-sym (+ i 1000))
                             (cons (list 'define (list fn-sym 'x 'y)
                                         (list 'let (list (list 't (list mac-sym 'x)))
                                               (list 'if (list '< 't 'y)
                                                     (list '* 't 2)
                                                     (list '+ 't 'y))))
                                   (cons (list 'define-syntax mac-sym
                                               (list 'syntax-rules '()
                                                     (list (list mac-sym 'v) (list '+ 'v i))))
                                         acc))))))))
       ;; Serialize source text to file and parse/expand/lower baseline
       (raw-text
         (let ((sp (open-output-string)))
           (for-each
             (lambda (f)
               (write f sp)
               (newline sp))
             hdr-forms)
           (get-output-string sp))))
  (sbi-write-text-file large-hdr-path raw-text)
  (let* ((compile-hdr-hir
           (lambda ()
             (let* ((parsed (sbi-read-forms-from-string raw-text))
                    (exp (expand-macros-in-forms parsed))
                    (rew (rewrite-top-level exp))
                    (des (desugar-all rew)))
               (anf-all (cp0-optimize (cp0-optimize des))))))
         (compiled-hir
           (sbi-load-or-build-pch
             large-pch-path
             (list large-hdr-path)
             compile-hdr-hir))
         (iters 3)
         ;; Measure raw parse + macro expand + rewrite + desugar + cp0 HIR (Cold Header Parse)
         (t0 (sbi-test-now-seconds))
         (cold-res
           (let cold-loop ((k 0) (last #f))
             (if (>= k iters)
                 last
                 (cold-loop (+ k 1) (compile-hdr-hir)))))
         (t1 (sbi-test-now-seconds))
         ;; Measure precompiled .sbi v2 binary cache reload (Warm PCH Load)
         (t2 (sbi-test-now-seconds))
         (warm-res
           (let warm-loop ((k 0) (last #f))
             (if (>= k iters)
                 last
                 (warm-loop (+ k 1) (sbi-read-file large-pch-path)))))
         (t3 (sbi-test-now-seconds))
         (cold-dt (let ((d (- t1 t0))) (if (<= d 0.0) 0.000001 d)))
         (warm-dt (let ((d (- t3 t2))) (if (<= d 0.0) 0.000001 d)))
         (speedup (/ cold-dt warm-dt)))
    (display "  [BENCH] 121-form header cold parse+HIR time (3x): ")
    (display cold-dt)
    (display "s\n")
    (display "  [BENCH] 121-form .sbi v2 PCH reload time (3x):  ")
    (display warm-dt)
    (display "s\n")
    (display "  [BENCH] PCH Speedup Ratio: ")
    (display speedup)
    (display "x\n")
    (sbi-assert-true "5.1 Re-parsed cold HIR equals cached .sbi HIR"
                     (sbi-equal? cold-res warm-res))
    (sbi-assert-true "5.2 .sbi v2 PCH reload achieves >= 5.0x speedup over raw parse+expand"
                     (>= speedup 5.0))))

;;; -----------------------------------------------------------------------
;;; Group 6: LTO Multi-Module LIR Merging & Legacy .sbi v1 Compatibility
;;; -----------------------------------------------------------------------
(sbi-print-group "--- Group 6: LTO Multi-Module Merging & Legacy .sbi v1 Compat ---")

(let* ((mod-a-lir
         (list '%lir-program
               '(strings ((str_a "mod_a")))
               '(stackmaps ())
               '(%lir-functions
                  (%lir-function mod_square
                    (params (x))
                    (frame-size 16)
                    (body
                      (%mov %rax %rdi)
                      (%imul %rax %rdi)
                      (%sar %rax 2)
                      (%return)))
                  (%lir-function mod_add_ten
                    (params (x))
                    (frame-size 16)
                    (body
                      (%mov %rax %rdi)
                      (%add %rax 40) ; 10 << 2 = 40 (tagged fixnum)
                      (%return))))
               '(%lir-main
                  (frame-size 16)
                  (body
                    (%mov %rax 0)
                    (%return)))))
       (mod-b-lir
         (list '%lir-program
               '(strings ((str_b "mod_b")))
               '(stackmaps ())
               '(%lir-functions)
               '(%lir-main
                  (frame-size 32)
                  (body
                    (%mov %rdi 24) ; tagged fixnum 6
                    (%direct-call mod_square 0)
                    (%mov %rdi %rax)
                    (%direct-call mod_add_ten 0)
                    (%return)))))
       (path-a "build/tmp_sbi_lto_a.sbi")
       (path-b "build/tmp_sbi_lto_b.sbi"))
  (sbi-write-file path-a mod-a-lir 'lir)
  (sbi-write-file path-b mod-b-lir 'lir)
  (let* ((loaded-a (sbi-read-file path-a))
         (loaded-b (sbi-read-file path-b))
         (merged (sbi-merge-lir-modules (list loaded-a loaded-b))))
    (sbi-assert-equal "6.1 LTO merged .sbi LIR modules execute together on VM (6^2 + 10 = 46)"
                      46
                      (eval-lir-program-unboxed merged))))

;; Legacy .sbi v1 fallback + binary sbi-import-forms
(let ((legacy-path "build/tmp_sbi_legacy_v1.sbi")
      (bin-path "build/tmp_sbi_forms_v2.sbi")
      (sample-forms '((define (inc-x x) (+ x 1))
                      (inc-x 41))))
  (sbi-write-text-file legacy-path ";;; Legacy SBI v1\n(define (legacy-fn x) (+ x 7))\n")
  (sbi-write-file bin-path sample-forms 'pch)
  (sbi-assert-false "6.2a Legacy text .sbi v1 is NOT reported as binary USBI"
                    (sbi-binary-file? legacy-path))
  (sbi-assert-true "6.2b Binary .sbi v2 IS reported as binary USBI"
                   (sbi-binary-file? bin-path))
  (let ((imp-v1 (sbi-import-forms legacy-path))
        (imp-v2 (sbi-import-forms bin-path)))
    (sbi-assert-equal "6.3a sbi-import-forms reads legacy .sbi v1 text forms"
                      '((define (legacy-fn x) (+ x 7)))
                      (map strip-source-loc imp-v1))
    (sbi-assert-equal "6.3b sbi-import-forms reads binary .sbi v2 forms"
                      sample-forms
                      imp-v2)))

;;; -----------------------------------------------------------------------
;;; Summary Report
;;; -----------------------------------------------------------------------
(newline)
(display "=======================================================\n")
(display " IR Serialization (.sbi v2) Summary: ")
(display (car *sbi-pass-count*))
(display "/")
(display (car *sbi-test-count*))
(display " passed.\n")
(display "=======================================================\n")
(if (not (= (car *sbi-pass-count*) (car *sbi-test-count*)))
    (error "Some IR Serialization tests failed!"))

;;; =======================================================================
;;; ULisp Test Suite: SRFI 124 Ephemerons & GC Coordination (Issue #856)
;;; Testing:
;;;   Group 1: Predicates and Accessors (make-ephemeron, ephemeron?, etc.)
;;;   Group 2: Immediate Values as Keys (fixnum, symbol, boolean, char, null)
;;;   Group 3: Ephemeron with Live Key through Dual-Space GC
;;;   Group 4: Ephemeron with Dead Key Reclaimed by GC (Broken state)
;;;   Group 5: Weak-Key Association List with Selective Key Death
;;;   Group 6: Cyclic Weak Key-Datum Graph (Key -> Datum -> Key)
;;;   Group 7: Ephemeron Chaining & Fixed-Point Resolution (E1 -> E2)
;;;   Group 8: Reference Barrier Behavior
;;;   Group 9: Multi-Cycle GC Stress & Stability
;;; Conforms to DSN-33 Architecture Specification & Barry Hayes (1997)
;;; =======================================================================

(test-begin "srfi-124-ephemerons")

(define-syntax assert-equal
  (syntax-rules ()
    ((assert-equal name actual expected)
     (test-equal name expected actual))))

(define-syntax assert-true
  (syntax-rules ()
    ((assert-true name val)
     (test-assert name val))))

(define-syntax assert-false
  (syntax-rules ()
    ((assert-false name val)
     (test-assert name (not val)))))

;; =======================================================================
;; Group 1: Predicates and Accessors
;; =======================================================================
(write-string "--- Group 1: Predicates and Accessors ---\n")

(define k1 (cons "key" 1))
(define d1 (cons "datum" 1))
(define e1 (make-ephemeron k1 d1))

(assert-true "1.1 ephemeron? on ephemeron" (ephemeron? e1))
(assert-false "1.2 ephemeron? on pair" (ephemeron? (cons 1 2)))
(assert-false "1.3 ephemeron? on vector" (ephemeron? (vector 1 2 3)))
(assert-false "1.4 ephemeron? on fixnum" (ephemeron? 42))
(assert-false "1.5 ephemeron? on null" (ephemeron? '()))
(assert-false "1.6 ephemeron? on boolean" (ephemeron? #t))
(assert-false "1.7 ephemeron? on string" (ephemeron? "str"))

(assert-false "1.8 ephemeron-broken? initially #f" (ephemeron-broken? e1))
(assert-true "1.9 ephemeron-key matches initial" (eq? (ephemeron-key e1) k1))
(assert-true "1.10 ephemeron-datum matches initial" (eq? (ephemeron-datum e1) d1))

;; =======================================================================
;; Group 2: Immediate Values as Keys (Always Reachable)
;; =======================================================================
(write-string "--- Group 2: Immediate Values as Keys ---\n")

(define e-fixnum (make-ephemeron 12345 (vector "datum-fixnum")))
(define e-sym    (make-ephemeron 'my-sym (vector "datum-sym")))
(define e-bool   (make-ephemeron #t (vector "datum-bool")))
(define e-char   (make-ephemeron #\Z (vector "datum-char")))
(define e-null   (make-ephemeron '() (vector "datum-null")))

;; Force full GC
(set-gc-debug-mode! #t)
(gc-collect! (%get-rsp))
(set-gc-debug-mode! #f)

(assert-false "2.1 fixnum key ephemeron not broken after GC" (ephemeron-broken? e-fixnum))
(assert-equal "2.2 fixnum key preserved" (ephemeron-key e-fixnum) 12345)
(assert-equal "2.3 fixnum datum preserved" (vector-ref (ephemeron-datum e-fixnum) 0) "datum-fixnum")

(assert-false "2.4 sym key ephemeron not broken after GC" (ephemeron-broken? e-sym))
(assert-equal "2.5 sym key preserved" (ephemeron-key e-sym) 'my-sym)
(assert-equal "2.6 sym datum preserved" (vector-ref (ephemeron-datum e-sym) 0) "datum-sym")

(assert-false "2.7 bool key ephemeron not broken after GC" (ephemeron-broken? e-bool))
(assert-equal "2.8 bool key preserved" (ephemeron-key e-bool) #t)

(assert-false "2.9 char key ephemeron not broken after GC" (ephemeron-broken? e-char))
(assert-equal "2.10 char key preserved" (ephemeron-key e-char) #\Z)

(assert-false "2.11 null key ephemeron not broken after GC" (ephemeron-broken? e-null))
(assert-equal "2.12 null key preserved" (ephemeron-key e-null) '())

;; =======================================================================
;; Group 3: Ephemeron with Live Heap Key through GC
;; =======================================================================
(write-string "--- Group 3: Ephemeron with Live Heap Key ---\n")

(define live-k (cons 'live 'token))
(define live-d (cons 'payload 'val))
(define e-live (make-ephemeron live-k live-d))

;; Force full GC while live-k is actively referenced
(set-gc-debug-mode! #t)
(gc-collect! (%get-rsp))
(set-gc-debug-mode! #f)

(assert-false "3.1 ephemeron not broken when key is live" (ephemeron-broken? e-live))
(assert-true "3.2 key preserved" (equal? (ephemeron-key e-live) (cons 'live 'token)))
(assert-true "3.3 datum preserved" (equal? (ephemeron-datum e-live) (cons 'payload 'val)))

;; Perform a second GC cycle
(set-gc-debug-mode! #t)
(gc-collect! (%get-rsp))
(set-gc-debug-mode! #f)
(assert-false "3.4 ephemeron still not broken after second GC" (ephemeron-broken? e-live))
(assert-true "3.5 datum still accessible" (equal? (ephemeron-datum e-live) (cons 'payload 'val)))

;; =======================================================================
;; Group 4: Ephemeron with Dead Heap Key Reclaimed by GC
;; =======================================================================
(write-string "--- Group 4: Ephemeron with Dead Key Reclaimed by GC ---\n")

(define (make-dead-ephemeron-scenario)
  (let* ((transient-key (cons 'ephemeral 'key-object))
         (datum-val (vector 'secret 'data)))
    (make-ephemeron transient-key datum-val)))

(define (test-dead-ephemeron-scenario)
  (let ((e-dead (make-dead-ephemeron-scenario)))
    (gc-collect! (%get-rsp))
    e-dead))

(define e-dead-res (test-dead-ephemeron-scenario))

(assert-true "4.1 ephemeron is broken after key reclaimed" (ephemeron-broken? e-dead-res))
(assert-false "4.2 ephemeron-key returns #f when broken" (ephemeron-key e-dead-res))
(assert-false "4.3 ephemeron-datum returns #f when broken" (ephemeron-datum e-dead-res))

;; Ensure broken state is idempotent across subsequent collections
(gc-collect! (%get-rsp))
(assert-true "4.4 ephemeron remains broken across another GC" (ephemeron-broken? e-dead-res))
(assert-false "4.5 ephemeron-key still #f" (ephemeron-key e-dead-res))
(assert-false "4.6 ephemeron-datum still #f" (ephemeron-datum e-dead-res))

;; =======================================================================
;; Group 5: Weak-Key Association List with Selective Key Death
;; =======================================================================
(write-string "--- Group 5: Weak-Key Association List ---\n")

(define (make-dead-ephemeron-bob)
  (let ((dead-k (cons 'user "bob-dead")))
    (make-ephemeron dead-k "metadata-bob")))

(define (test-weak-alist-scenario)
  (let* ((k1 (cons 'user "alice"))
         (k3 (cons 'user "charlie"))
         (e1 (make-ephemeron k1 "metadata-alice"))
         (e2 (make-dead-ephemeron-bob))
         (e3 (make-ephemeron k3 "metadata-charlie"))
         (weak-alist (list e1 e2 e3)))
    (gc-collect! (%get-rsp))
    (cons (cons k1 k3) weak-alist)))

(define alist-res (test-weak-alist-scenario))
(define keep-pair (car alist-res))
(define weak-alist (cdr alist-res))

(define e-alice   (list-ref weak-alist 0))
(define e-bob     (list-ref weak-alist 1))
(define e-charlie (list-ref weak-alist 2))

(assert-false "5.1 alice entry kept alive" (ephemeron-broken? e-alice))
(assert-equal "5.2 alice datum preserved" (ephemeron-datum e-alice) "metadata-alice")

(assert-true "5.3 bob entry broken" (ephemeron-broken? e-bob))
(assert-false "5.4 bob datum cleared" (ephemeron-datum e-bob))

(assert-false "5.5 charlie entry kept alive" (ephemeron-broken? e-charlie))
(assert-equal "5.6 charlie datum preserved" (ephemeron-datum e-charlie) "metadata-charlie")

;; =======================================================================
;; Group 6: Cyclic Weak Key-Datum Graph (Key -> Datum -> Key)
;; =======================================================================
(write-string "--- Group 6: Cyclic Weak Key-Datum Graph ---\n")

;; Case A: Cyclic pair where key is also externally referenced
(define (make-cyclic-ephemeron-with-external-key)
  (let* ((key-obj (vector 'cyclic-key))
         (datum-obj (cons key-obj 'datum-referencing-key))
         (ephem (make-ephemeron key-obj datum-obj)))
    (cons key-obj ephem)))

(define (test-cyclic-live-scenario)
  (let* ((pair-res (make-cyclic-ephemeron-with-external-key))
         (external-k (car pair-res))
         (e-cyclic-live (cdr pair-res)))
    (gc-collect! (%get-rsp))
    (cons external-k e-cyclic-live)))

(define live-cyclic-res (test-cyclic-live-scenario))
(define external-k (car live-cyclic-res))
(define e-cyclic-live (cdr live-cyclic-res))

(assert-false "6.1 cyclic ephemeron with external key remains alive"
              (ephemeron-broken? e-cyclic-live))
(assert-true "6.2 datum car points back to key"
             (eq? (car (ephemeron-datum e-cyclic-live)) external-k))

;; Case B: Cyclic pair with NO external reference (classic GC leak trap in weak refs)
(define (make-dead-cyclic-ephemeron)
  (let* ((k (vector 'self-cyclic-key))
         (d (cons k 'points-to-k))
         (e (make-ephemeron k d)))
    e))

(define (test-dead-cyclic-scenario)
  (let ((e-dead (make-dead-cyclic-ephemeron)))
    (gc-collect! (%get-rsp))
    e-dead))

(define e-cyclic-dead (test-dead-cyclic-scenario))

(assert-true "6.3 cyclic ephemeron without external reference is broken"
             (ephemeron-broken? e-cyclic-dead))
(assert-false "6.4 cyclic datum severed (#f)"
              (ephemeron-datum e-cyclic-dead))
(assert-false "6.5 cyclic key severed (#f)"
              (ephemeron-key e-cyclic-dead))

;; =======================================================================
;; Group 7: Ephemeron Chaining & Fixed-Point Resolution (E1 -> E2)
;; =======================================================================
(write-string "--- Group 7: Ephemeron Chaining & Fixed-Point Loop ---\n")

;; E1: key=K1, datum=K2
;; E2: key=K2, datum="final-value"
;; K1 is externally live. K2 is ONLY reachable through E1's datum.
;; Without a fixed-point loop, Cheney scan would fail to realize K2 is reachable
;; and prematurely break E2!
(define K1 (cons 'chain 'root))

(define (make-chain-ephemerons root-k)
  (let* ((K2 (vector 'intermediate-key))
         (e2 (make-ephemeron K2 "final-value"))
         (e1 (make-ephemeron root-k K2)))
    (cons e1 e2)))

(define chain-pair (make-chain-ephemerons K1))
(define e-chain1 (car chain-pair))
(define e-chain2 (cdr chain-pair))

;; Run GC
(set-gc-debug-mode! #t)
(gc-collect! (%get-rsp))
(set-gc-debug-mode! #f)

(assert-false "7.1 chain E1 alive" (ephemeron-broken? e-chain1))
(assert-false "7.2 chain E2 alive via fixed-point resolution" (ephemeron-broken? e-chain2))
(assert-equal "7.3 chain E2 datum preserved" (ephemeron-datum e-chain2) "final-value")

;; =======================================================================
;; Group 8: Reference Barrier Behavior
;; =======================================================================
(write-string "--- Group 8: Reference Barrier Behavior ---\n")

(define b-key (cons 'barrier 'key))
(define e-barrier (make-ephemeron b-key 999))

(define barrier-ret (reference-barrier b-key))
(assert-true "8.1 reference-barrier returns key unchanged" (eq? barrier-ret b-key))

(set-gc-debug-mode! #t)
(gc-collect! (%get-rsp))
(set-gc-debug-mode! #f)
(assert-false "8.2 barrier key ephemeron remains alive" (ephemeron-broken? e-barrier))
(assert-equal "8.3 datum is 999" (ephemeron-datum e-barrier) 999)

;; =======================================================================
;; Group 9: Multi-Cycle GC Stress & Stability
;; =======================================================================
(write-string "--- Group 9: Multi-Cycle GC Stress & Stability ---\n")

;; Allocate 100 ephemerons, keep even-indexed keys in a list, let odd-indexed keys die
(define (run-stress-test)
  (let loop ((i 0) (kept-keys '()) (ephems '()))
    (if (< i 100)
        (let* ((k (cons 'key i))
               (d (vector 'datum i))
               (e (make-ephemeron k d)))
          (if (= (modulo i 2) 0)
              (loop (+ i 1) (cons k kept-keys) (cons e ephems))
              (loop (+ i 1) kept-keys (cons e ephems))))
        (cons kept-keys ephems))))

(define (test-stress-scenario)
  (let* ((stress-res (run-stress-test))
         (kept (car stress-res))
         (ephems (cdr stress-res)))
    (gc-collect! (%get-rsp))
    (gc-collect! (%get-rsp))
    (cons kept ephems)))

(define stress-result (test-stress-scenario))
(define stress-kept (car stress-result))
(define stress-ephems (cdr stress-result))

;; Verify results
(define verified-counts
  (let count-loop ((lst stress-ephems) (alive-count 0) (broken-count 0))
    (if (null? lst)
        (cons alive-count broken-count)
        (let ((e (car lst)))
          (if (ephemeron-broken? e)
              (count-loop (cdr lst) alive-count (+ broken-count 1))
              (count-loop (cdr lst) (+ alive-count 1) broken-count))))))

(assert-equal "9.1 Exactly 50 even ephemerons survived" (car verified-counts) 50)
(assert-equal "9.2 Exactly 50 odd ephemerons broken" (cdr verified-counts) 50)

(test-end "srfi-124-ephemerons")

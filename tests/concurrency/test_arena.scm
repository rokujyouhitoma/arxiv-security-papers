;;; =======================================================================
;;; Unit & Endurance Test Suite: Process-Local Ephemeral Arena (Issue #630)
;;; Conforms to DSN-37 Section 5, Section 13.4 & Section 14.2 (Phase 0 Task 0.1)
;;; =======================================================================

(load "ulisp/runtime/concurrency/arena.scm")

(define *test-arena-failures* (vector 0))
(define *test-arena-passes* (vector 0))

(define (assert-true val msg)
  (if (not val)
      (begin
        (vector-set! *test-arena-failures* 0 (+ (vector-ref *test-arena-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-arena-passes* 0 (+ (vector-ref *test-arena-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(define (assert-equal actual expected msg)
  (if (not (eqv? actual expected))
      (begin
        (vector-set! *test-arena-failures* 0 (+ (vector-ref *test-arena-failures* 0) 1))
        (write-string "FAIL: ")
        (write-string msg)
        (write-string " (expected ")
        (write-string (number->string expected))
        (write-string ", got ")
        (write-string (number->string actual))
        (write-string ")\n")
        (flush-output-port)
        #f)
      (begin
        (vector-set! *test-arena-passes* 0 (+ (vector-ref *test-arena-passes* 0) 1))
        (write-string "PASS: ")
        (write-string msg)
        (write-char #\newline)
        (flush-output-port)
        #t)))

(write-string "=======================================================\n")
(write-string " Starting Process-Local Ephemeral Arena Test Suite (#630)\n")
(write-string "=======================================================\n")
(flush-output-port)

;; -----------------------------------------------------------------------
;; Group 1: Arena Initialization & Record Predicates
;; -----------------------------------------------------------------------
(write-string "--- Group 1: Arena Initialization & Predicates ---\n")
(flush-output-port)

(let ((a-default (make-task-arena))
      (a-2k      (make-task-arena 2048))
      (a-8k      (make-task-arena 8192))
      (a-odd     (make-task-arena 2050))
      (a-dsn37   (make-task-arena 131072 0 4096)))
  (assert-true (task-arena? a-default) "default arena satisfies task-arena?")
  (assert-true (not (task-arena? 42)) "fixnum is not task-arena?")
  (assert-true (not (task-arena? (vector 1 2 3))) "raw vector is not task-arena?")
  (assert-equal (arena-capacity a-default) 4096 "default arena capacity is 4096 (4KB)")
  (assert-equal (arena-offset a-default) 0 "default arena initial offset is 0")
  (assert-true (arena-empty? a-default) "default arena is initially empty")
  (assert-equal (arena-capacity a-2k) 2048 "2KB arena capacity is 2048")
  (assert-equal (arena-capacity a-8k) 8192 "8KB arena capacity is 8192")
  (assert-equal (arena-capacity a-odd) 2056 "unaligned initial capacity 2050 rounds up to 2056")
  (assert-equal (arena-base a-dsn37) 131072 "DSN-37 3-arg constructor sets base address")
  (assert-equal (arena-capacity a-dsn37) 4096 "DSN-37 3-arg constructor sets capacity"))

;; -----------------------------------------------------------------------
;; Group 2: 8-Byte Boundary Alignment & Fast Bump Allocation
;; -----------------------------------------------------------------------
(write-string "--- Group 2: 8-Byte Alignment & Bump Allocation ---\n")
(flush-output-port)

(let* ((arena (make-task-arena 4096))
       (base  (arena-base arena))
       (p1    (arena-allocate! arena 1))    ; size 1  -> aligned 8,  off 0..8
       (p2    (arena-allocate! arena 3))    ; size 3  -> aligned 8,  off 8..16
       (p3    (arena-allocate! arena 7))    ; size 7  -> aligned 8,  off 16..24
       (p4    (arena-allocate! arena 8))    ; size 8  -> aligned 8,  off 24..32
       (p5    (arena-allocate! arena 9))    ; size 9  -> aligned 16, off 32..48
       (p6    (arena-allocate! arena 15))   ; size 15 -> aligned 16, off 48..64
       (p7    (arena-allocate! arena 16))   ; size 16 -> aligned 16, off 64..80
       (p8    (arena-allocate! arena 17))   ; size 17 -> aligned 24, off 80..104
       (p9    (arena-allocate! arena 24 16)) ; 16B aligned -> off 112..144
       (p10   (arena-allocate! arena 32 64))) ; 64B aligned -> off 192..256
  (assert-equal (modulo p1 8) 0 "p1 (1B) is 8-byte aligned")
  (assert-equal (modulo p2 8) 0 "p2 (3B) is 8-byte aligned")
  (assert-equal (modulo p3 8) 0 "p3 (7B) is 8-byte aligned")
  (assert-equal (modulo p4 8) 0 "p4 (8B) is 8-byte aligned")
  (assert-equal (modulo p5 8) 0 "p5 (9B) is 8-byte aligned")
  (assert-equal (modulo p6 8) 0 "p6 (15B) is 8-byte aligned")
  (assert-equal (modulo p7 8) 0 "p7 (16B) is 8-byte aligned")
  (assert-equal (modulo p8 8) 0 "p8 (17B) is 8-byte aligned")
  (assert-equal (- p1 base) 0 "p1 offset is 0")
  (assert-equal (- p2 base) 8 "p2 offset is 8")
  (assert-equal (- p3 base) 16 "p3 offset is 16")
  (assert-equal (- p4 base) 24 "p4 offset is 24")
  (assert-equal (- p5 base) 32 "p5 offset is 32")
  (assert-equal (- p6 base) 48 "p6 offset is 48")
  (assert-equal (- p7 base) 64 "p7 offset is 64")
  (assert-equal (- p8 base) 80 "p8 offset is 80")
  (assert-equal (modulo p9 16) 0 "p9 is 16-byte aligned")
  (assert-equal (modulo p10 64) 0 "p10 is 64-byte cache-line aligned"))

;; -----------------------------------------------------------------------
;; Group 3: Arena Memory Read / Write Isolation
;; -----------------------------------------------------------------------
(write-string "--- Group 3: Arena Memory Read / Write Isolation ---\n")
(flush-output-port)

(let* ((arena (make-task-arena 2048))
       (a1    (arena-allocate! arena 8))
       (a2    (arena-allocate! arena 8))
       (a3    (arena-allocate! arena 16)))
  (arena-u64-set! arena a1 123456789)
  (arena-u64-set! arena a2 987654321)
  (arena-u8-set!  arena a3 42)
  (arena-u8-set!  arena (+ a3 15) 255)
  (assert-equal (arena-u64-ref arena a1) 123456789 "u64 read/write at a1 preserved")
  (assert-equal (arena-u64-ref arena a2) 987654321 "u64 read/write at a2 preserved without clobbering a1")
  (assert-equal (arena-u8-ref arena a3) 42 "u8 read/write at a3[0] preserved")
  (assert-equal (arena-u8-ref arena (+ a3 15)) 255 "u8 read/write at a3[15] preserved"))

;; -----------------------------------------------------------------------
;; Group 4: O(1) Instant Reset & Secure Zero-Scrubbing Reset
;; -----------------------------------------------------------------------
(write-string "--- Group 4: O(1) Instant Reset & Secure Scrubbing ---\n")
(flush-output-port)

(let* ((arena (make-task-arena 2048))
       (p1    (arena-allocate! arena 128))
       (p2    (arena-allocate! arena 256)))
  (arena-u8-set! arena p1 170)
  (arena-u8-set! arena p2 187)
  (assert-equal (arena-offset arena) 384 "offset before reset is 384")
  (assert-true (arena-reset! arena) "arena-reset! returns #t")
  (assert-equal (arena-offset arena) 0 "arena-offset after arena-reset! is 0")
  (assert-true (arena-empty? arena) "arena is empty after arena-reset!")
  (assert-equal (arena-reset-count arena) 1 "arena-reset-count incremented to 1")
  (let ((p1-reused (arena-allocate! arena 128)))
    (assert-equal p1-reused p1 "re-allocated block after reset gets identical base address")
    (arena-u8-set! arena p1-reused 99)
    (assert-equal (arena-u8-ref arena p1-reused) 99 "value written before secure reset is 99")
    (assert-true (arena-secure-reset! arena) "arena-secure-reset! returns #t")
    (assert-equal (arena-offset arena) 0 "offset after arena-secure-reset! is 0")
    (assert-equal (bytevector-u8-ref (arena-buffer arena) 0) 0 "secure reset scrubbed underlying buffer byte to 0")))

;; -----------------------------------------------------------------------
;; Group 5: Chained Overflow Chunk Fallback (8KB Chunks)
;; -----------------------------------------------------------------------
(write-string "--- Group 5: Chained Overflow Chunk Fallback ---\n")
(flush-output-port)

(let ((arena (make-task-arena 2048)))
  ;; Allocate 4 * 512 = 2048 bytes (fills primary 2KB arena exactly)
  (let ((c1 (arena-allocate! arena 512))
        (c2 (arena-allocate! arena 512))
        (c3 (arena-allocate! arena 512))
        (c4 (arena-allocate! arena 512)))
    (assert-equal (arena-offset arena) 2048 "primary 2KB arena filled to 2048 bytes")
    (assert-equal (arena-chunk-count arena) 0 "no overflow chunks allocated yet")
    ;; Allocate 6 more * 512 = 3072 bytes (triggers 8KB overflow chunk #1)
    (let ((o1 (arena-allocate! arena 512))
          (o2 (arena-allocate! arena 512))
          (o3 (arena-allocate! arena 2048)))
      (assert-equal (arena-chunk-count arena) 1 "1st overflow chunk (8KB) allocated")
      (assert-equal (modulo o1 8) 0 "overflow chunk allocation o1 is 8-byte aligned")
      (assert-equal (modulo o2 8) 0 "overflow chunk allocation o2 is 8-byte aligned")
      (assert-equal (modulo o3 8) 0 "overflow chunk allocation o3 is 8-byte aligned")
      (arena-u64-set! arena c1 11111)
      (arena-u64-set! arena o1 22222)
      (arena-u64-set! arena o3 33333)
      (assert-equal (arena-u64-ref arena c1) 11111 "primary arena data intact after overflow")
      (assert-equal (arena-u64-ref arena o1) 22222 "overflow chunk data at o1 intact")
      (assert-equal (arena-u64-ref arena o3) 33333 "overflow chunk data at o3 intact")
      ;; Trigger 2nd overflow chunk by allocating 6000 bytes (exceeding remaining 8192 - 3072 = 5120 bytes)
      (let ((o4 (arena-allocate! arena 6000)))
        (assert-equal (arena-chunk-count arena) 2 "2nd overflow chunk allocated")
        (assert-equal (modulo o4 8) 0 "2nd overflow chunk allocation o4 is 8-byte aligned")
        (assert-equal (arena-used-bytes arena) 11120 "total used bytes across primary + 2 chunks is 11120")
        ;; Reset reclaims all overflow chunks in O(1)
        (arena-reset! arena)
        (assert-equal (arena-offset arena) 0 "primary offset reset to 0")
        (assert-equal (arena-chunk-count arena) 0 "all overflow chunks reclaimed (chunk-count = 0)")
        (assert-true (null? (arena-chunks arena)) "arena-chunks list is empty after reset")
        (assert-equal (arena-used-bytes arena) 0 "used-bytes is 0 after reset")))))

;; -----------------------------------------------------------------------
;; Group 6: Security & Boundary Guards (CWE-190 / CWE-400 / CWE-787)
;; -----------------------------------------------------------------------
(write-string "--- Group 6: Security & Boundary Guards ---\n")
(flush-output-port)

(let ((arena (make-task-arena 2048)))
  (let ((zero-err (guard (ex (else 'caught-zero))
                    (arena-allocate! arena 0))))
    (assert-equal zero-err 'caught-zero "rejects zero-size allocation (CWE-190)"))
  (let ((neg-err (guard (ex (else 'caught-neg))
                   (arena-allocate! arena -16))))
    (assert-equal neg-err 'caught-neg "rejects negative-size allocation (CWE-190)"))
  (let ((huge-err (guard (ex (else 'caught-huge))
                    (arena-allocate! arena 2097152))))
    (assert-equal huge-err 'caught-huge "rejects oversized >1MB allocation (CWE-190)"))
  (let ((align-err (guard (ex (else 'caught-align))
                     (arena-allocate! arena 16 12))))
    (assert-equal align-err 'caught-align "rejects non-power-of-two alignment"))
  (let ((oob-err (guard (ex (else 'caught-oob))
                   (arena-u8-ref arena (arena-base arena)))))
    (assert-equal oob-err 'caught-oob "rejects reading unallocated arena address (CWE-787)"))
  ;; Test CWE-400 max-chunks guard
  (arena-max-chunks-set! arena 2)
  (arena-allocate! arena 2048) ; fills primary
  (arena-allocate! arena 8192) ; chunk 1
  (arena-allocate! arena 8192) ; chunk 2
  (let ((max-chunk-err (guard (ex (else 'caught-max-chunks))
                         (arena-allocate! arena 64))))
    (assert-equal max-chunk-err 'caught-max-chunks "enforces max overflow chunks limit (CWE-400)"))
  (arena-reset! arena))

;; -----------------------------------------------------------------------
;; Group 7: 1,000,000 Allocations & Resets Endurance (0-Byte Leak DoD)
;; -----------------------------------------------------------------------
(write-string "--- Group 7: 1,000,000 Allocations & Resets Endurance Test ---\n")
(flush-output-port)

(let ((arena (make-task-arena 4096))
      (outer-cycles 10000)
      (inner-allocs 100))
  (let outer-loop ((c 0))
    (if (< c outer-cycles)
        (begin
          (let inner-loop ((i 0))
            (if (< i inner-allocs)
                (begin
                  ;; Allocate 24 bytes (aligned to 24 bytes = 3 * 8B, 100 * 24 = 2400B <= 4096B)
                  (arena-allocate! arena 24)
                  (inner-loop (+ i 1)))))
          (arena-reset! arena)
          (outer-loop (+ c 1)))))
  (assert-equal (arena-offset arena) 0 "0 bytes leaked in primary arena after 1,000,000 allocations")
  (assert-equal (arena-chunk-count arena) 0 "0 overflow chunks leaked after 1,000,000 allocations")
  (assert-equal (arena-used-bytes arena) 0 "0 used bytes retained after 1,000,000 allocations")
  (assert-equal (arena-reset-count arena) 10000 "exact 10,000 arena resets recorded")
  (assert-equal (arena-total-allocated arena) 24000000 "exact 24,000,000 cumulative bytes bump-allocated"))

(write-string "=======================================================\n")
(if (= (vector-ref *test-arena-failures* 0) 0)
    (begin
      (write-string " SUCCESS: ALL PROCESS-LOCAL EPHEMERAL ARENA TESTS PASSED!\n")
      (write-string "=======================================================\n")
      (flush-output-port)
      #t)
    (begin
      (write-string " FAILURE: Some arena tests failed!\n")
      (write-string "=======================================================\n")
      (flush-output-port)
      (exit 1)))


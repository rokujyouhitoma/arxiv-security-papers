;;; =======================================================================
;;; ULisp Pure Scheme Runtime: entry.scm (Pre-Scheme Architecture)
;;; Conforms to DSN-33 Architecture Specification & Issue #580
;;;
;;; Standalone execution entrypoint and process orchestration:
;;; runtime-main, argv parsing, heap bootstrap, entry dispatch, clean exit
;;; =======================================================================

(define (scheme-entry heap)
  0)

(define (runtime-main entry-proc argc argv-ptr quiet-mode profile-id debug-gc)
  ;; 1. Initialize Generational Heap & GC State
  (let ((heap (runtime-init-heap 16777216 profile-id debug-gc)))
    ;; 2. Execute compiled Scheme Entrypoint
    (let ((result (if (procedure? entry-proc)
                      (entry-proc heap)
                      (scheme-entry heap))))
      ;; 3. Display Result if not quiet
      (if (not quiet-mode)
          (runtime-print-value result))
      ;; 4. Check DEBUG_GC diagnostic output
      (if (not (= (bitwise-and (runtime-gc-debug-gc) 1) 0))
          (begin
            (sys-write-string "[DEBUG_GC] Execution complete. Rescued unmapped pointers: ")
            (sys-write-fixnum (quotient (runtime-gc-debug-gc) 2))
            (sys-write-char #\newline)
            (sys-flush)))
      ;; 5. Flush and exit cleanly
      (runtime-flush)
      0)))

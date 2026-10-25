;;; =======================================================================
;;; ULisp Standard Library & Runtime Entry Point: stdlib_entry.scm
;;; Conforms to DSN-33 Architecture Specification & Issue #607
;;; Contains standard libraries and runtime subsystems for modular compilation (ulisp_stdlib.o)
;;; =======================================================================

(!gc none)

;; Standard Library Modules
(include "lib/posix.scm")
(include "lib/list.scm")
(include "lib/string.scm")
(include "lib/port.scm")
(include "lib/printer.scm")
(include "lib/reader.scm")
(include "lib/equality.scm")
(include "lib/predicates.scm")
(include "lib/math.scm")
(include "lib/bytevector.scm")
(include "lib/vector.scm")
(include "lib/promise.scm")
(include "lib/exception.scm")
(include "lib/values.scm")
(include "lib/continuation.scm")
(include "lib/parameter.scm")
(include "lib/gc.scm")

;; Runtime Subsystems
(include "runtime/gc.scm")
(include "runtime/io.scm")
(include "runtime/printer.scm")
(include "runtime/entry.scm")

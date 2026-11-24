;;; =======================================================================
;;; ULisp Native AOT C99 Compiler Driver Entry Point: c_driver_entry.scm
;;; Conforms to DSN-33 Architecture Specification & Issue #932
;;; Linked with ulisp_stdlib.o, compiler modules, c99_vm.o, c99_frontend.o, c99_driver.o
;;; =======================================================================

(!gc none)

(exit (c-driver-cli-main (cdr (command-line))))

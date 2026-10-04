"""ILISP (Intelligence LISP) Kernel.

An AI-native Lisp dialect adhering to R7RS-small Scheme with zero-copy Python interop.
"""

from ilisp.env import Environment, make_initial_env
from ilisp.evaluator import eval_expr
from ilisp.reader import LispSyntaxError, Reader, read_all, read_one
from ilisp.repl import repl, run_file, run_string
from ilisp.types import (
    NIL,
    Cell,
    Cons,
    NilType,
    Primitive,
    Procedure,
    SequenceView,
    SourceLocation,
    Symbol,
    car,
    cdr,
    is_null,
    is_pair,
    to_lisp_list,
    to_py_list,
)

__version__ = "0.1.0"

__all__ = [
    "Environment",
    "make_initial_env",
    "eval_expr",
    "Reader",
    "read_one",
    "read_all",
    "LispSyntaxError",
    "repl",
    "run_string",
    "run_file",
    "Symbol",
    "Cons",
    "NIL",
    "NilType",
    "Cell",
    "SequenceView",
    "SourceLocation",
    "Procedure",
    "Primitive",
    "car",
    "cdr",
    "is_pair",
    "is_null",
    "to_lisp_list",
    "to_py_list",
]

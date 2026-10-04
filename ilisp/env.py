"""Lexical Environment and Core Primitives for Kernel ILISP.

This module implements nested lexical scopes, variable binding, Cell boxing,
and standard R7RS-small core primitives plus Python zero-copy interop.
"""

from __future__ import annotations

import importlib
import os
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Union

from ilisp.char import (
    char_alphabetic_p,
    char_ci_eq_p,
    char_ci_ge_p,
    char_ci_gt_p,
    char_ci_le_p,
    char_ci_lt_p,
    char_downcase,
    char_eq_p,
    char_foldcase,
    char_ge_p,
    char_gt_p,
    char_le_p,
    char_lower_case_p,
    char_lt_p,
    char_numeric_p,
    char_p,
    char_to_integer,
    char_upcase,
    char_upper_case_p,
    char_whitespace_p,
    digit_value,
    integer_to_char,
    list_to_string,
    make_string,
    string_append,
    string_ci_eq_p,
    string_ci_ge_p,
    string_ci_gt_p,
    string_ci_le_p,
    string_ci_lt_p,
    string_constructor,
    string_copy,
    string_copy_bang,
    string_downcase,
    string_eq_p,
    string_fill_bang,
    string_foldcase,
    string_for_each,
    string_ge_p,
    string_gt_p,
    string_le_p,
    string_length,
    string_lt_p,
    string_map,
    string_p,
    string_ref,
    string_set_bang,
    string_to_list,
    string_to_vector,
    string_upcase,
    substring,
    vector_to_string,
)
from ilisp.numbers import (
    complex_p,
    even_p,
    exact_integer_p,
    exact_integer_sqrt,
    exact_p,
    finite_p,
    floor_div,
    floor_quotient,
    floor_remainder,
    imag_part,
    inexact_p,
    infinite_p,
    integer_p,
    make_polar,
    make_rectangular,
    nan_p,
    negative_p,
    num_abs,
    num_acos,
    num_angle,
    num_asin,
    num_atan,
    num_ceiling,
    num_cos,
    num_div,
    num_eq,
    num_exact,
    num_exp,
    num_expt,
    num_floor,
    num_gcd,
    num_ge,
    num_gt,
    num_inexact,
    num_lcm,
    num_le,
    num_log,
    num_lt,
    num_magnitude,
    num_max,
    num_min,
    num_modulo,
    num_round,
    num_sin,
    num_sqrt,
    num_square,
    num_tan,
    num_truncate,
    number_p,
    number_to_string,
    odd_p,
    positive_p,
    rational_p,
    real_p,
    real_part,
    string_to_number,
    truncate_div,
    truncate_quotient,
    truncate_remainder,
    zero_p,
)
from ilisp.types import (
    NIL,
    Bytevector,
    Cell,
    Char,
    Cons,
    Continuation,
    ErrorObject,
    EscapeContinuation,
    MutableString,
    Parameter,
    Primitive,
    Procedure,
    Promise,
    Record,
    RecordType,
    SchemeException,
    SequenceView,
    Symbol,
    Values,
    Vector,
    car,
    cdr,
    is_error_object,
    is_file_error,
    is_null,
    is_pair,
    is_parameter,
    is_promise,
    is_read_error,
    is_record,
    is_record_type,
    set_car,
    set_cdr,
    string_val,
    to_lisp_list,
    to_py_list,
)


class Environment:
    """Lexical Environment frame with parent scoping chain."""

    def __init__(
        self,
        parent: Optional[Environment] = None,
        bindings: Optional[Dict[Symbol, Any]] = None,
    ) -> None:
        self.parent: Optional[Environment] = parent
        self.bindings: Dict[Symbol, Any] = bindings if bindings is not None else {}

    def define(self, sym: Symbol, val: Any) -> None:
        """Bind variable in the current local environment frame."""
        self.bindings[sym] = val

    def lookup(self, sym: Symbol) -> Any:
        """Lookup variable recursively through lexical chain; unwrap Cell if boxed."""
        curr: Optional[Environment] = self
        while curr is not None:
            if sym in curr.bindings:
                bound = curr.bindings[sym]
                if isinstance(bound, Cell):
                    return bound.get()
                return bound
            curr = curr.parent
        raise NameError(f"Unbound variable: '{sym.name}'")

    def lookup_cell(self, sym: Symbol) -> Optional[Cell]:
        """Lookup Cell container for variable if it is boxed."""
        curr: Optional[Environment] = self
        while curr is not None:
            if sym in curr.bindings:
                bound = curr.bindings[sym]
                if isinstance(bound, Cell):
                    return bound
                return None
            curr = curr.parent
        return None

    def set(self, sym: Symbol, val: Any) -> None:
        """Mutate existing variable via set!; updates Cell value if boxed."""
        curr: Optional[Environment] = self
        while curr is not None:
            if sym in curr.bindings:
                bound = curr.bindings[sym]
                if isinstance(bound, Cell):
                    bound.set(val)
                else:
                    curr.bindings[sym] = val
                return
            curr = curr.parent
        raise NameError(f"Cannot set! unbound variable: '{sym.name}'")

    def extend(self, params: Sequence[Symbol], args: Sequence[Any]) -> Environment:
        """Create a child environment binding parameters to arguments."""
        if len(params) != len(args):
            raise TypeError(
                f"Argument count mismatch: expected {len(params)}, got {len(args)}"
            )
        new_bindings = {p: a for p, a in zip(params, args)}
        return Environment(parent=self, bindings=new_bindings)


def make_initial_env(preload_stdlib: bool = True) -> Environment:
    """Construct top-level global environment preloaded with 23 core primitives and Python interop."""
    env = Environment()

    # --- 1. Pair & List Primitives ---
    def prim_cons(a: Any, b: Any) -> Cons:
        return Cons(a, b)

    def prim_car(p: Any) -> Any:
        return car(p)

    def prim_cdr(p: Any) -> Any:
        return cdr(p)

    # --- 2-step accessors (R7RS 6.4, (scheme base)) ---
    def prim_caar(p: Any) -> Any:
        return car(car(p))

    def prim_cadr(p: Any) -> Any:
        return car(cdr(p))

    def prim_cdar(p: Any) -> Any:
        return cdr(car(p))

    def prim_cddr(p: Any) -> Any:
        return cdr(cdr(p))

    # --- 3-step accessors (R7RS 7.1.1, (scheme cxr)) ---
    def prim_caaar(p: Any) -> Any:
        return car(car(car(p)))

    def prim_caadr(p: Any) -> Any:
        return car(car(cdr(p)))

    def prim_cadar(p: Any) -> Any:
        return car(cdr(car(p)))

    def prim_caddr(p: Any) -> Any:
        return car(cdr(cdr(p)))

    def prim_cdaar(p: Any) -> Any:
        return cdr(car(car(p)))

    def prim_cdadr(p: Any) -> Any:
        return cdr(car(cdr(p)))

    def prim_cddar(p: Any) -> Any:
        return cdr(cdr(car(p)))

    def prim_cdddr(p: Any) -> Any:
        return cdr(cdr(cdr(p)))

    # --- 4-step accessors (R7RS 7.1.1, (scheme cxr)) ---
    def prim_caaaar(p: Any) -> Any:
        return car(car(car(car(p))))

    def prim_caaadr(p: Any) -> Any:
        return car(car(car(cdr(p))))

    def prim_caadar(p: Any) -> Any:
        return car(car(cdr(car(p))))

    def prim_caaddr(p: Any) -> Any:
        return car(car(cdr(cdr(p))))

    def prim_cadaar(p: Any) -> Any:
        return car(cdr(car(car(p))))

    def prim_cadadr(p: Any) -> Any:
        return car(cdr(car(cdr(p))))

    def prim_caddar(p: Any) -> Any:
        return car(cdr(cdr(car(p))))

    def prim_cadddr(p: Any) -> Any:
        return car(cdr(cdr(cdr(p))))

    def prim_cdaaar(p: Any) -> Any:
        return cdr(car(car(car(p))))

    def prim_cdaadr(p: Any) -> Any:
        return cdr(car(car(cdr(p))))

    def prim_cdadar(p: Any) -> Any:
        return cdr(car(cdr(car(p))))

    def prim_cdaddr(p: Any) -> Any:
        return cdr(car(cdr(cdr(p))))

    def prim_cddaar(p: Any) -> Any:
        return cdr(cdr(car(car(p))))

    def prim_cddadr(p: Any) -> Any:
        return cdr(cdr(car(cdr(p))))

    def prim_cdddar(p: Any) -> Any:
        return cdr(cdr(cdr(car(p))))

    def prim_cddddr(p: Any) -> Any:
        return cdr(cdr(cdr(cdr(p))))

    def prim_set_car_bang(pair: Any, val: Any) -> Any:
        set_car(pair, val)
        return NIL

    def prim_set_cdr_bang(pair: Any, val: Any) -> Any:
        set_cdr(pair, val)
        return NIL

    def prim_pair_p(x: Any) -> bool:
        return is_pair(x)

    def prim_null_p(x: Any) -> bool:
        return is_null(x)

    def prim_list(*args: Any) -> Any:
        return to_lisp_list(args)

    def prim_list_p(obj: Any) -> bool:
        """R7RS 6.4 list? predicate with Floyd's cycle detection algorithm."""
        if is_null(obj):
            return True
        if not is_pair(obj):
            return False
        slow = obj
        fast = obj
        while is_pair(fast):
            fast = cdr(fast)
            if is_null(fast):
                return True
            if not is_pair(fast):
                return False
            fast = cdr(fast)
            if is_null(fast):
                return True
            slow = cdr(slow)
            if slow is fast:
                return False
        return is_null(fast)

    def prim_make_list(k: int, fill: Any = NIL) -> Any:
        if not isinstance(k, int) or k < 0:
            raise ValueError(
                f"make-list: expected non-negative integer length, got {k!r}"
            )
        res: Any = NIL
        for _ in range(k):
            res = Cons(fill, res)
        return res

    def prim_list_tail(lst: Any, k: int) -> Any:
        if not isinstance(k, int) or k < 0:
            raise ValueError(
                f"list-tail: expected non-negative integer index, got {k!r}"
            )
        curr = lst
        for i in range(k):
            if not is_pair(curr):
                raise IndexError(
                    f"list-tail: index {k} exceeds length of list (stopped at step {i})"
                )
            curr = cdr(curr)
        return curr

    def prim_list_ref(lst: Any, k: int) -> Any:
        tail = prim_list_tail(lst, k)
        if not is_pair(tail):
            raise IndexError(f"list-ref: index {k} out of range")
        return car(tail)

    def prim_list_set_bang(lst: Any, k: int, val: Any) -> Any:
        tail = prim_list_tail(lst, k)
        set_car(tail, val)
        return NIL

    def prim_list_copy(obj: Any) -> Any:
        if not is_pair(obj):
            return obj
        head: Optional[Cons] = None
        tail: Optional[Cons] = None
        curr = obj
        while isinstance(curr, Cons):
            new_cell = Cons(curr.car, NIL)
            if head is None:
                head = new_cell
            else:
                assert tail is not None
                tail.cdr = new_cell
            tail = new_cell
            curr = curr.cdr
        if tail is not None:
            tail.cdr = curr
        return head if head is not None else obj

    # --- 2. Symbol & String Primitives ---
    def prim_symbol_p(x: Any) -> bool:
        return isinstance(x, Symbol)

    def prim_symbol_to_string(s: Symbol) -> str:
        if not isinstance(s, Symbol):
            raise TypeError(f"symbol->string expected symbol, got {s!r}")
        return s.name

    def prim_symbol_eq(s1: Any, s2: Any, *rest: Any) -> bool:
        args = (s1, s2) + rest
        for arg in args:
            if not isinstance(arg, Symbol):
                raise TypeError(f"symbol=? expected symbol argument, got {arg!r}")
        first_name = args[0].name
        return all(arg.name == first_name for arg in args[1:])

    # --- 3. Equality & Boolean Primitives ---
    def prim_eq_p(a: Any, b: Any) -> bool:
        if isinstance(a, Symbol) and isinstance(b, Symbol):
            return a is b
        if a is NIL and b is NIL:
            return True
        return a is b

    def prim_eqv_p(a: Any, b: Any) -> bool:
        if isinstance(a, Symbol) and isinstance(b, Symbol):
            return a is b
        if isinstance(a, (int, float, str, bool, Char, complex)) and isinstance(
            b, (int, float, str, bool, Char, complex)
        ):
            return type(a) is type(b) and a == b
        if isinstance(a, MutableString) and isinstance(b, MutableString):
            return a is b
        return a is b

    def prim_equal_p(a: Any, b: Any) -> bool:
        if prim_eqv_p(a, b):
            return True
        if isinstance(a, (str, MutableString)) and isinstance(b, (str, MutableString)):
            return string_val(a) == string_val(b)
        if is_pair(a) and is_pair(b):
            return prim_equal_p(car(a), car(b)) and prim_equal_p(cdr(a), cdr(b))
        if isinstance(a, Vector) and isinstance(b, Vector):
            if len(a) != len(b):
                return False
            return all(prim_equal_p(a[i], b[i]) for i in range(len(a)))
        if isinstance(a, Bytevector) and isinstance(b, Bytevector):
            return a == b
        if isinstance(a, Record) and isinstance(b, Record):
            if a.record_type is not b.record_type:
                return False
            return all(
                prim_equal_p(a.slots[i], b.slots[i]) for i in range(len(a.slots))
            )
        if isinstance(a, ErrorObject) and isinstance(b, ErrorObject):
            return (
                a.kind == b.kind
                and a.message == b.message
                and prim_equal_p(a.irritants, b.irritants)
            )
        return False

    def prim_boolean_p(x: Any) -> bool:
        return isinstance(x, bool)

    def prim_boolean_eq(b1: Any, b2: Any, *rest: Any) -> bool:
        args = (b1, b2) + rest
        for arg in args:
            if not isinstance(arg, bool):
                raise TypeError(f"boolean=? expected boolean argument, got {arg!r}")
        first_val = args[0]
        return all(arg == first_val for arg in args[1:])

    def prim_not(x: Any) -> bool:
        # In Scheme, only #f is false. Everything else (including 0 and '()) is truthy!
        return x is False

    # --- 4. Arithmetic & Comparison Primitives ---
    def prim_add(*nums: Union[int, float, complex]) -> Union[int, float, complex]:
        total: Union[int, float, complex] = 0
        for n in nums:
            total += n
        return total

    def prim_sub(
        first: Union[int, float, complex], *rest: Union[int, float, complex]
    ) -> Union[int, float, complex]:
        if not rest:
            return -first
        total = first
        for n in rest:
            total -= n
        return total

    def prim_mul(*nums: Union[int, float, complex]) -> Union[int, float, complex]:
        prod: Union[int, float, complex] = 1
        for n in nums:
            prod *= n
        return prod

    def prim_quotient(a: int, b: int) -> int:
        return int(a // b)

    def prim_remainder(a: int, b: int) -> int:
        return int(a % b)

    def prim_num_eq(a: Union[int, float], b: Union[int, float]) -> bool:
        return a == b

    def prim_num_lt(a: Union[int, float], b: Union[int, float]) -> bool:
        return a < b

    def prim_num_gt(a: Union[int, float], b: Union[int, float]) -> bool:
        return a > b

    # --- 5. I/O Primitives (R7RS) ---
    from ilisp import port as port_mod

    def prim_display(x: Any, port: Optional[port_mod.TextualOutputPort] = None) -> None:
        port_mod.display(x, port)

    def prim_newline(port: Optional[port_mod.TextualOutputPort] = None) -> None:
        port_mod.newline(port)

    def prim_write(x: Any, port: Optional[port_mod.TextualOutputPort] = None) -> None:
        port_mod.write_val(x, port)

    def prim_write_simple(
        x: Any, port: Optional[port_mod.TextualOutputPort] = None
    ) -> None:
        port_mod.write_simple(x, port)

    def prim_write_shared(
        x: Any, port: Optional[port_mod.TextualOutputPort] = None
    ) -> None:
        port_mod.write_shared(x, port)

    def prim_read(port: Optional[port_mod.TextualInputPort] = None) -> Any:
        return port_mod.read_datum(port)

    def prim_read_char(port: Optional[port_mod.TextualInputPort] = None) -> Any:
        return port_mod.read_char(port)

    def prim_peek_char(port: Optional[port_mod.TextualInputPort] = None) -> Any:
        return port_mod.peek_char(port)

    def prim_read_line(port: Optional[port_mod.TextualInputPort] = None) -> Any:
        return port_mod.read_line(port)

    def prim_read_string(
        k: int, port: Optional[port_mod.TextualInputPort] = None
    ) -> Any:
        return port_mod.read_string(k, port)

    def prim_char_ready_p(port: Optional[port_mod.TextualInputPort] = None) -> bool:
        return port_mod.char_ready_p(port)

    def prim_write_char(
        ch: str, port: Optional[port_mod.TextualOutputPort] = None
    ) -> None:
        port_mod.write_char(ch, port)

    def prim_write_string(s: Any, *args: Any) -> None:
        port: Optional[port_mod.TextualOutputPort] = None
        start: int = 0
        end: Optional[int] = None
        if len(args) == 1:
            port = args[0]
        elif len(args) == 2:
            port, start = args[0], int(args[1])
        elif len(args) == 3:
            port, start, end = args[0], int(args[1]), int(args[2])
        elif len(args) > 3:
            raise TypeError(
                f"write-string: expected 1 to 4 arguments, got {1 + len(args)}"
            )
        port_mod.write_string(s, port=port, start=start, end=end)

    def prim_read_bytevector(k: int, *args: Any) -> Any:
        port = args[0] if args else None
        return port_mod.read_bytevector(k, port)

    def prim_read_bytevector_bang(bv: Any, *args: Any) -> Any:
        port = None
        start = 0
        end = None
        if len(args) == 1:
            port = args[0]
        elif len(args) == 2:
            port, start = args[0], int(args[1])
        elif len(args) == 3:
            port, start, end = args[0], int(args[1]), int(args[2])
        elif len(args) > 3:
            raise TypeError(
                f"read-bytevector!: expected 1 to 4 arguments, got {1 + len(args)}"
            )
        return port_mod.read_bytevector_bang(bv, port=port, start=start, end=end)

    def prim_write_bytevector(bv: Any, *args: Any) -> None:
        port = None
        start = 0
        end = None
        if len(args) == 1:
            port = args[0]
        elif len(args) == 2:
            port, start = args[0], int(args[1])
        elif len(args) == 3:
            port, start, end = args[0], int(args[1]), int(args[2])
        elif len(args) > 3:
            raise TypeError(
                f"write-bytevector: expected 1 to 4 arguments, got {1 + len(args)}"
            )
        port_mod.write_bytevector(bv, port=port, start=start, end=end)

    def prim_flush_output_port(
        port: Optional[port_mod.TextualOutputPort] = None,
    ) -> None:
        port_mod.flush_output_port(port)

    def prim_eof_object() -> Any:
        return port_mod.eof_object()

    def prim_eof_object_p(x: Any) -> bool:
        return port_mod.eof_object_p(x)

    # --- 6. Bytevector Primitives (R7RS 6.9) ---
    def prim_bytevector_p(obj: Any) -> bool:
        return isinstance(obj, Bytevector)

    def prim_make_bytevector(k: int, byte: int = 0) -> Bytevector:
        if not isinstance(k, int) or k < 0:
            raise ValueError(
                f"make-bytevector: expected non-negative integer length, got {k!r}"
            )
        if not (0 <= byte <= 255):
            raise ValueError(
                f"make-bytevector: fill byte out of range 0..255, got {byte!r}"
            )
        return Bytevector(bytearray([byte] * k))

    def prim_bytevector(*bytes_args: int) -> Bytevector:
        for b in bytes_args:
            if not isinstance(b, int) or not (0 <= b <= 255):
                raise ValueError(f"bytevector: octet out of range 0..255, got {b!r}")
        return Bytevector(bytearray(bytes_args))

    def prim_bytevector_length(bv: Bytevector) -> int:
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"bytevector-length: expected Bytevector, got {type(bv).__name__}"
            )
        return len(bv)

    def prim_bytevector_u8_ref(bv: Bytevector, k: int) -> int:
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"bytevector-u8-ref: expected Bytevector, got {type(bv).__name__}"
            )
        if not (0 <= k < len(bv)):
            raise IndexError(
                f"bytevector-u8-ref: index {k} out of range (length {len(bv)})"
            )
        return bv[k]

    def prim_bytevector_u8_set_bang(bv: Bytevector, k: int, byte: int) -> None:
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"bytevector-u8-set!: expected Bytevector, got {type(bv).__name__}"
            )
        if not (0 <= k < len(bv)):
            raise IndexError(
                f"bytevector-u8-set!: index {k} out of range (length {len(bv)})"
            )
        if not (0 <= byte <= 255):
            raise ValueError(
                f"bytevector-u8-set!: byte out of range 0..255, got {byte!r}"
            )
        bv[k] = byte

    def prim_bytevector_copy(
        bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> Bytevector:
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"bytevector-copy: expected Bytevector, got {type(bv).__name__}"
            )
        sub = bv.data[start:end]
        return Bytevector(sub)

    def prim_bytevector_copy_bang(
        to: Bytevector,
        at: int,
        from_bv: Bytevector,
        start: int = 0,
        end: Optional[int] = None,
    ) -> None:
        if not isinstance(to, Bytevector) or not isinstance(from_bv, Bytevector):
            raise TypeError("bytevector-copy!: expected Bytevector instances")
        sub = from_bv.data[start:end]
        if at + len(sub) > len(to):
            raise IndexError(
                "bytevector-copy!: target bytevector too short for copied segment"
            )
        to.data[at : at + len(sub)] = sub

    def prim_bytevector_append(*bvs: Bytevector) -> Bytevector:
        res = bytearray()
        for bv in bvs:
            if not isinstance(bv, Bytevector):
                raise TypeError(
                    f"bytevector-append: expected Bytevector, got {type(bv).__name__}"
                )
            res.extend(bv.data)
        return Bytevector(res)

    def prim_utf8_to_string(
        bv: Bytevector, start: int = 0, end: Optional[int] = None
    ) -> str:
        if not isinstance(bv, Bytevector):
            raise TypeError(
                f"utf8->string: expected Bytevector, got {type(bv).__name__}"
            )
        sub = bv.data[start:end]
        return sub.decode("utf-8")

    def prim_string_to_utf8(
        s: str, start: int = 0, end: Optional[int] = None
    ) -> Bytevector:
        if not isinstance(s, str):
            raise TypeError(f"string->utf8: expected str, got {type(s).__name__}")
        sub = s[start:end]
        return Bytevector(sub.encode("utf-8"))

    # --- 7. Python Zero-Copy & Interop Primitives ---
    def prim_sequence_view(seq: Sequence[Any], offset: int = 0) -> SequenceView:
        return SequenceView(seq, offset=offset)

    def prim_py_import(mod_name: Union[Symbol, str]) -> Any:
        name = mod_name.name if isinstance(mod_name, Symbol) else str(mod_name)
        return importlib.import_module(name)

    def prim_py_call(obj: Any, method: Union[Symbol, str], *args: Any) -> Any:
        method_name = method.name if isinstance(method, Symbol) else str(method)
        fn = getattr(obj, method_name)
        # Convert Scheme lists to python collections if needed
        unwrapped_args = [to_py_list(arg) if is_pair(arg) else arg for arg in args]
        return fn(*unwrapped_args)

    def prim_py_get(obj: Any, attr: Union[Symbol, str]) -> Any:
        attr_name = attr.name if isinstance(attr, Symbol) else str(attr)
        if isinstance(obj, dict):
            return obj.get(attr_name)
        return getattr(obj, attr_name)

    def prim_py_set_bang(obj: Any, attr: Union[Symbol, str], val: Any) -> None:
        attr_name = attr.name if isinstance(attr, Symbol) else str(attr)
        if isinstance(obj, dict):
            obj[attr_name] = val
        else:
            setattr(obj, attr_name, val)

    def prim_py_eval(expr_str: str) -> Any:
        return eval(expr_str)  # nosec

    def prim_load(filepath: str) -> Any:
        from ilisp.evaluator import eval_expr
        from ilisp.reader import read_all

        with open(filepath, "r", encoding="utf-8") as f:
            code = f.read()
        exprs = read_all(code, filename=filepath)
        res: Any = NIL
        for expr in exprs:
            res = eval_expr(expr, env)
        return res

    def prim_num_le(*args: Union[int, float]) -> bool:
        if len(args) < 2:
            return True
        for i in range(len(args) - 1):
            if not (args[i] <= args[i + 1]):
                return False
        return True

    def prim_num_ge(*args: Union[int, float]) -> bool:
        if len(args) < 2:
            return True
        for i in range(len(args) - 1):
            if not (args[i] >= args[i + 1]):
                return False
        return True

    # Vectors (R7RS)
    def prim_vector_p(x: Any) -> bool:
        return isinstance(x, Vector)

    def prim_make_vector(k: int, fill: Any = NIL) -> Vector:
        return Vector([fill] * k)

    def prim_vector(*args: Any) -> Vector:
        return Vector(list(args))

    def prim_vector_length(vec: Any) -> int:
        if not isinstance(vec, Vector):
            raise TypeError(f"vector-length expected vector, got {type(vec).__name__}")
        return len(vec)

    def prim_vector_ref(vec: Any, k: int) -> Any:
        if not isinstance(vec, Vector):
            raise TypeError(f"vector-ref expected vector, got {type(vec).__name__}")
        return vec[k]

    def prim_vector_set_bang(vec: Any, k: int, val: Any) -> Any:
        if not isinstance(vec, Vector):
            raise TypeError(f"vector-set! expected vector, got {type(vec).__name__}")
        vec[k] = val
        return NIL

    def prim_vector_to_list(vec: Any) -> Any:
        if not isinstance(vec, Vector):
            raise TypeError(f"vector->list expected vector, got {type(vec).__name__}")
        return to_lisp_list(vec.elements)

    def prim_list_to_vector(lst: Any) -> Vector:
        return Vector(to_py_list(lst))

    def prim_vector_copy(vec: Any, start: int = 0, end: Optional[int] = None) -> Vector:
        if not isinstance(vec, Vector):
            raise TypeError(f"vector-copy expected vector, got {type(vec).__name__}")
        end_idx = len(vec) if end is None else end
        if not (0 <= start <= end_idx <= len(vec)):
            raise IndexError(
                f"vector-copy: invalid range [{start}:{end_idx}] for vector of length {len(vec)}"
            )
        return Vector(vec.elements[start:end_idx])

    def prim_vector_copy_bang(
        to: Any,
        at: int,
        from_vec: Any,
        start: int = 0,
        end: Optional[int] = None,
    ) -> None:
        if not isinstance(to, Vector) or not isinstance(from_vec, Vector):
            raise TypeError("vector-copy! expected vector arguments")
        end_idx = len(from_vec) if end is None else end
        if not (0 <= start <= end_idx <= len(from_vec)):
            raise IndexError(
                f"vector-copy!: invalid source range [{start}:{end_idx}] for length {len(from_vec)}"
            )
        count = end_idx - start
        if not (0 <= at and at + count <= len(to)):
            raise IndexError(
                f"vector-copy!: destination index {at} with length {count} exceeds vector of length {len(to)}"
            )
        # Copy to temporary buffer to safely handle overlapping ranges
        copied = list(from_vec.elements[start:end_idx])
        to.elements[at : at + count] = copied

    def prim_vector_fill_bang(
        vec: Any, fill: Any, start: int = 0, end: Optional[int] = None
    ) -> None:
        if not isinstance(vec, Vector):
            raise TypeError(f"vector-fill! expected vector, got {type(vec).__name__}")
        end_idx = len(vec) if end is None else end
        if not (0 <= start <= end_idx <= len(vec)):
            raise IndexError(
                f"vector-fill!: invalid range [{start}:{end_idx}] for length {len(vec)}"
            )
        for i in range(start, end_idx):
            vec.elements[i] = fill

    def prim_vector_append(*vecs: Any) -> Vector:
        res_elements: List[Any] = []
        for v in vecs:
            if not isinstance(v, Vector):
                raise TypeError(
                    f"vector-append expected vector, got {type(v).__name__}"
                )
            res_elements.extend(v.elements)
        return Vector(res_elements)

    def prim_vector_map(proc: Any, *vecs: Any) -> Vector:
        from ilisp.evaluator import _apply_procedure

        if not vecs:
            raise TypeError("vector-map requires at least one vector")
        for v in vecs:
            if not isinstance(v, Vector):
                raise TypeError(f"vector-map expected vector, got {type(v).__name__}")
        min_len = min(len(v) for v in vecs)
        res_elements: List[Any] = []
        for i in range(min_len):
            args = [v[i] for v in vecs]
            if isinstance(proc, Procedure):
                val = _apply_procedure(proc, args)
            elif callable(proc):
                val = proc(*args)
            else:
                raise TypeError(f"vector-map: proc must be procedure, got {proc!r}")
            res_elements.append(val)
        return Vector(res_elements)

    def prim_vector_for_each(proc: Any, *vecs: Any) -> None:
        from ilisp.evaluator import _apply_procedure

        if not vecs:
            raise TypeError("vector-for-each requires at least one vector")
        for v in vecs:
            if not isinstance(v, Vector):
                raise TypeError(
                    f"vector-for-each expected vector, got {type(v).__name__}"
                )
        min_len = min(len(v) for v in vecs)
        for i in range(min_len):
            args = [v[i] for v in vecs]
            if isinstance(proc, Procedure):
                _apply_procedure(proc, args)
            elif callable(proc):
                proc(*args)
            else:
                raise TypeError(
                    f"vector-for-each: proc must be procedure, got {proc!r}"
                )

    # Multiple Return Values (R7RS)
    def prim_values(*args: Any) -> Any:
        if len(args) == 1:
            return args[0]
        return Values(*args)

    def prim_call_with_values(producer: Any, consumer: Any) -> Any:
        from ilisp.evaluator import _apply_procedure

        if isinstance(producer, Procedure):
            prod_val = _apply_procedure(producer, [])
        elif callable(producer):
            prod_val = producer()
        else:
            raise TypeError(f"producer must be callable, got {producer!r}")

        if isinstance(prod_val, Values):
            arg_list = list(prod_val.values)
        else:
            arg_list = [prod_val]

        if isinstance(consumer, Procedure):
            return _apply_procedure(consumer, arg_list)
        elif callable(consumer):
            return consumer(*arg_list)
        raise TypeError(f"consumer must be callable, got {consumer!r}")

    # Continuations (R7RS One-shot Escape)
    cont_counter = 0

    def prim_call_cc(proc: Any) -> Any:
        nonlocal cont_counter
        cont_counter += 1
        cid = f"cc_{cont_counter}"
        cont = Continuation(cid)
        try:
            if isinstance(proc, Procedure):
                from ilisp.evaluator import _apply_procedure

                return _apply_procedure(proc, [cont])
            elif callable(proc):
                return proc(cont)
            raise TypeError(f"call/cc expects procedure, got {proc!r}")
        except EscapeContinuation as esc:
            if esc.cont_id == cid:
                return esc.value
            raise
        finally:
            cont.active = False

    def prim_dynamic_wind(before: Any, thunk: Any, after: Any) -> Any:
        from ilisp.evaluator import _apply_procedure

        # 1. Run before-thunk
        if isinstance(before, Procedure):
            _apply_procedure(before, [])
        elif callable(before):
            before()
        else:
            raise TypeError(f"dynamic-wind: before must be callable, got {before!r}")

        try:
            # 2. Run body thunk
            if isinstance(thunk, Procedure):
                return _apply_procedure(thunk, [])
            elif callable(thunk):
                return thunk()
            raise TypeError(f"dynamic-wind: thunk must be callable, got {thunk!r}")
        finally:
            # 3. Always run after-thunk (upon normal exit, exception, or continuation escape)
            if isinstance(after, Procedure):
                _apply_procedure(after, [])
            elif callable(after):
                after()
            else:
                raise TypeError(f"dynamic-wind: after must be callable, got {after!r}")

    def prim_make_parameter(init: Any, converter: Optional[Any] = None) -> Parameter:
        return Parameter(init, converter=converter)

    def prim_parameter_p(x: Any) -> bool:
        return is_parameter(x)

    # Procedure Application (R7RS 6.4)
    def prim_apply(proc: Any, *args: Any) -> Any:
        from ilisp.evaluator import _apply_procedure

        if not args:
            raise TypeError("apply requires at least 2 arguments (proc, args)")
        call_args: List[Any] = list(args[:-1])
        last_arg = args[-1]
        call_args.extend(to_py_list(last_arg))
        if isinstance(proc, Procedure):
            return _apply_procedure(proc, call_args)
        elif callable(proc):
            return proc(*call_args)
        raise TypeError(f"apply: expected procedure, got {proc!r}")

    # Delayed Evaluation (R7RS 4.2.5 & 6.10)
    def prim_promise_p(x: Any) -> bool:
        return is_promise(x)

    def prim_make_promise(x: Any) -> Promise:
        if isinstance(x, Promise):
            return x
        return Promise(done=True, value=x)

    def prim_make_promise_from_thunk(thunk: Any) -> Promise:
        from ilisp.evaluator import _apply_procedure

        if isinstance(thunk, Procedure):

            def py_thunk() -> Any:
                return _apply_procedure(thunk, [])

            return Promise(thunk=py_thunk)
        elif callable(thunk):
            return Promise(thunk=thunk)
        raise TypeError(f"make-promise-from-thunk: expected procedure, got {thunk!r}")

    def prim_force(x: Any) -> Any:
        if is_promise(x):
            return x.force()
        return x

    # --- Record Type Primitives (R7RS 5.5 & 6.x) ---
    def prim_make_record_type(name: Any, fields: Any) -> RecordType:
        if not isinstance(name, (str, Symbol)):
            raise TypeError(
                f"make-record-type: name must be symbol or string, got {name!r}"
            )
        field_list: List[Union[str, Symbol]] = []
        if is_pair(fields) or is_null(fields):
            field_list = to_py_list(fields)
        elif isinstance(fields, (list, tuple)):
            field_list = list(fields)
        else:
            raise TypeError(f"make-record-type: fields must be a list, got {fields!r}")
        for f in field_list:
            if not isinstance(f, (str, Symbol)):
                raise TypeError(
                    f"make-record-type: field name must be symbol or string, got {f!r}"
                )
        return RecordType(name, field_list)

    def prim_record_type_p(x: Any) -> bool:
        return is_record_type(x)

    def prim_record_p(x: Any) -> bool:
        return is_record(x)

    def prim_record_type(rec: Any) -> RecordType:
        if not isinstance(rec, Record):
            raise TypeError(f"record-type: expected Record, got {rec!r}")
        return rec.record_type

    def prim_record_type_name(rtd: Any) -> Symbol:
        if not isinstance(rtd, RecordType):
            raise TypeError(f"record-type-name: expected RecordType, got {rtd!r}")
        return Symbol.intern(rtd.name)

    def prim_record_type_field_names(rtd: Any) -> Any:
        if not isinstance(rtd, RecordType):
            raise TypeError(
                f"record-type-field-names: expected RecordType, got {rtd!r}"
            )
        return to_lisp_list([Symbol.intern(f) for f in rtd.fields])

    def prim_make_record(rtd: Any, *initial_slots: Any) -> Record:
        if not isinstance(rtd, RecordType):
            raise TypeError(f"make-record: expected RecordType, got {rtd!r}")
        if initial_slots:
            if len(initial_slots) == 1 and (
                is_pair(initial_slots[0]) or is_null(initial_slots[0])
            ):
                slots = to_py_list(initial_slots[0])
            else:
                slots = list(initial_slots)
            return Record(rtd, slots)
        return Record(rtd)

    def prim_record_ref(rec: Any, field: Any) -> Any:
        if not isinstance(rec, Record):
            raise TypeError(f"record-ref: expected Record, got {rec!r}")
        if isinstance(field, (int, str, Symbol)):
            return rec.get_field(field)
        raise TypeError(
            f"record-ref: field must be symbol, string, or integer index, got {field!r}"
        )

    def prim_record_set_bang(rec: Any, field: Any, val: Any) -> Any:
        if not isinstance(rec, Record):
            raise TypeError(f"record-set!: expected Record, got {rec!r}")
        if isinstance(field, (int, str, Symbol)):
            rec.set_field(field, val)
            return val
        raise TypeError(
            f"record-set!: field must be symbol, string, or integer index, got {field!r}"
        )

    def prim_record_predicate(rtd: Any) -> Primitive:
        if not isinstance(rtd, RecordType):
            raise TypeError(f"record-predicate: expected RecordType, got {rtd!r}")
        target_rtd = rtd

        def pred(x: Any) -> bool:
            return isinstance(x, Record) and x.record_type is target_rtd

        return Primitive(f"{target_rtd.name}?", pred)

    def prim_record_accessor(rtd: Any, field: Any) -> Primitive:
        if not isinstance(rtd, RecordType):
            raise TypeError(f"record-accessor: expected RecordType, got {rtd!r}")
        fname = field.name if isinstance(field, Symbol) else str(field)
        if not rtd.has_field(fname):
            raise KeyError(
                f"record-accessor: record type {rtd.name} has no field {fname}"
            )
        fidx = rtd.field_index(fname)
        target_rtd = rtd

        def accessor(rec: Any) -> Any:
            if not isinstance(rec, Record) or rec.record_type is not target_rtd:
                raise TypeError(
                    f"accessor for {target_rtd.name}.{fname} expected {target_rtd.name} instance, got {rec!r}"
                )
            return rec.slots[fidx]

        return Primitive(f"{target_rtd.name}-{fname}", accessor)

    def prim_record_modifier(rtd: Any, field: Any) -> Primitive:
        if not isinstance(rtd, RecordType):
            raise TypeError(f"record-modifier: expected RecordType, got {rtd!r}")
        fname = field.name if isinstance(field, Symbol) else str(field)
        if not rtd.has_field(fname):
            raise KeyError(
                f"record-modifier: record type {rtd.name} has no field {fname}"
            )
        fidx = rtd.field_index(fname)
        target_rtd = rtd

        def modifier(rec: Any, val: Any) -> Any:
            if not isinstance(rec, Record) or rec.record_type is not target_rtd:
                raise TypeError(
                    f"modifier for {target_rtd.name}.{fname} expected {target_rtd.name} instance, got {rec!r}"
                )
            rec.slots[fidx] = val
            return val

        return Primitive(f"{target_rtd.name}-{fname}-set!", modifier)

    def prim_record_constructor(rtd: Any, fields_spec: Any = None) -> Primitive:
        if not isinstance(rtd, RecordType):
            raise TypeError(f"record-constructor: expected RecordType, got {rtd!r}")
        target_rtd = rtd

        if fields_spec is None:
            field_names = list(target_rtd.fields)
        elif is_pair(fields_spec) or is_null(fields_spec):
            field_names = [
                f.name if isinstance(f, Symbol) else str(f)
                for f in to_py_list(fields_spec)
            ]
        elif isinstance(fields_spec, (list, tuple)):
            field_names = [
                f.name if isinstance(f, Symbol) else str(f) for f in fields_spec
            ]
        else:
            raise TypeError(
                f"record-constructor: fields must be a list or None, got {fields_spec!r}"
            )

        arg_to_slot: List[int] = []
        for fn in field_names:
            if not target_rtd.has_field(fn):
                raise KeyError(
                    f"record-constructor: record type {target_rtd.name} has no field {fn}"
                )
            arg_to_slot.append(target_rtd.field_index(fn))

        def constructor(*args: Any) -> Record:
            if len(args) != len(arg_to_slot):
                raise TypeError(
                    f"Constructor for {target_rtd.name} expected {len(arg_to_slot)} arguments, got {len(args)}"
                )
            rec = Record(target_rtd)
            for slot_idx, val in zip(arg_to_slot, args):
                rec.slots[slot_idx] = val
            return rec

        return Primitive(f"make-{target_rtd.name}", constructor)

    # Exceptions & Conditions (R7RS 6.11)
    def prim_raise(datum: Any) -> Any:
        raise SchemeException(datum)

    def prim_with_exception_handler(handler: Any, thunk: Any) -> Any:
        from ilisp.evaluator import _apply_procedure
        from ilisp.reader import LispSyntaxError

        try:
            if isinstance(thunk, Procedure):
                return _apply_procedure(thunk, [])
            elif callable(thunk):
                return thunk()
            raise TypeError(f"thunk must be callable, got {thunk!r}")
        except SchemeException as se:
            if isinstance(handler, Procedure):
                return _apply_procedure(handler, [se.datum])
            elif callable(handler):
                return handler(se.datum)
            raise
        except (LispSyntaxError, SyntaxError) as syn_err:
            err_obj = ErrorObject(str(syn_err), NIL, kind="read")
            if isinstance(handler, Procedure):
                return _apply_procedure(handler, [err_obj])
            elif callable(handler):
                return handler(err_obj)
            raise
        except (
            FileNotFoundError,
            PermissionError,
            IsADirectoryError,
            OSError,
        ) as os_err:
            err_obj = ErrorObject(str(os_err), NIL, kind="file")
            if isinstance(handler, Procedure):
                return _apply_procedure(handler, [err_obj])
            elif callable(handler):
                return handler(err_obj)
            raise
        except Exception as py_err:
            err_obj = ErrorObject(str(py_err), NIL, kind="generic")
            if isinstance(handler, Procedure):
                return _apply_procedure(handler, [err_obj])
            elif callable(handler):
                return handler(err_obj)
            raise

    def prim_error(msg: Any, *args: Any) -> Any:
        message_str = msg if isinstance(msg, str) else str(msg)
        irritants_list = to_lisp_list(args) if args else NIL
        err_obj = ErrorObject(message_str, irritants_list, kind="generic")
        raise SchemeException(err_obj)

    def prim_syntax_error(msg: Any, *args: Any) -> Any:
        message_str = msg if isinstance(msg, str) else str(msg)
        irritants_list = to_lisp_list(args) if args else NIL
        err_obj = ErrorObject(message_str, irritants_list, kind="read")
        raise SchemeException(err_obj)

    def prim_error_object_p(x: Any) -> bool:
        return is_error_object(x)

    def prim_error_object_message(x: Any) -> str:
        if not is_error_object(x):
            raise TypeError(f"error-object-message: expected error-object, got {x!r}")
        return str(x.message)

    def prim_error_object_irritants(x: Any) -> Any:
        if not is_error_object(x):
            raise TypeError(f"error-object-irritants: expected error-object, got {x!r}")
        return x.irritants

    def prim_read_error_p(x: Any) -> bool:
        return is_read_error(x)

    def prim_file_error_p(x: Any) -> bool:
        return is_file_error(x)

    def prim_file_error(msg: Any, *args: Any) -> Any:
        message_str = msg if isinstance(msg, str) else str(msg)
        irritants_list = to_lisp_list(args) if args else NIL
        err_obj = ErrorObject(message_str, irritants_list, kind="file")
        raise SchemeException(err_obj)

    def prim_read_error(msg: Any, *args: Any) -> Any:
        message_str = msg if isinstance(msg, str) else str(msg)
        irritants_list = to_lisp_list(args) if args else NIL
        err_obj = ErrorObject(message_str, irritants_list, kind="read")
        raise SchemeException(err_obj)

    # --- System, Time, and Process-Context Primitives (R7RS 6.14) ---
    def prim_current_second() -> float:
        return time.time()

    def prim_current_jiffy() -> int:
        return time.monotonic_ns()

    def prim_jiffies_per_second() -> int:
        return 1_000_000_000

    def prim_get_environment_variable(name: Any) -> Any:
        if not isinstance(name, (str, MutableString)):
            raise TypeError(f"get-environment-variable: expected string, got {name!r}")
        s = string_val(name)
        val = os.environ.get(s)
        if val is None:
            return False
        return val

    def prim_get_environment_variables() -> Any:
        pairs = [Cons(k, v) for k, v in os.environ.items()]
        return to_lisp_list(pairs)

    def prim_command_line() -> Any:
        return to_lisp_list(list(sys.argv))

    def prim_exit(obj: Any = True) -> None:
        code: int = 0
        if obj is True:
            code = 0
        elif obj is False:
            code = 1
        elif isinstance(obj, int):
            code = obj
        sys.exit(code)

    def prim_emergency_exit(obj: Any = True) -> None:
        code: int = 0
        if obj is True:
            code = 0
        elif obj is False:
            code = 1
        elif isinstance(obj, int):
            code = obj
        os._exit(code)

    # Register all primitives
    primitives: Dict[str, Callable[..., Any]] = {
        # Pairs and Lists (R7RS 6.4)
        "cons": prim_cons,
        "car": prim_car,
        "cdr": prim_cdr,
        # 2-step accessors (R7RS 6.4, (scheme base))
        "caar": prim_caar,
        "cadr": prim_cadr,
        "cdar": prim_cdar,
        "cddr": prim_cddr,
        # 3-step accessors (R7RS 7.1.1, (scheme cxr))
        "caaar": prim_caaar,
        "caadr": prim_caadr,
        "cadar": prim_cadar,
        "caddr": prim_caddr,
        "cdaar": prim_cdaar,
        "cdadr": prim_cdadr,
        "cddar": prim_cddar,
        "cdddr": prim_cdddr,
        # 4-step accessors (R7RS 7.1.1, (scheme cxr))
        "caaaar": prim_caaaar,
        "caaadr": prim_caaadr,
        "caadar": prim_caadar,
        "caaddr": prim_caaddr,
        "cadaar": prim_cadaar,
        "cadadr": prim_cadadr,
        "caddar": prim_caddar,
        "cadddr": prim_cadddr,
        "cdaaar": prim_cdaaar,
        "cdaadr": prim_cdaadr,
        "cdadar": prim_cdadar,
        "cdaddr": prim_cdaddr,
        "cddaar": prim_cddaar,
        "cddadr": prim_cddadr,
        "cdddar": prim_cdddar,
        "cddddr": prim_cddddr,
        "set-car!": prim_set_car_bang,
        "set-cdr!": prim_set_cdr_bang,
        "pair?": prim_pair_p,
        "null?": prim_null_p,
        "list?": prim_list_p,
        "list": prim_list,
        "make-list": prim_make_list,
        "list-tail": prim_list_tail,
        "list-ref": prim_list_ref,
        "list-set!": prim_list_set_bang,
        "list-copy": prim_list_copy,
        # Symbols
        "symbol?": prim_symbol_p,
        "symbol=?": prim_symbol_eq,
        "symbol->string": prim_symbol_to_string,
        # Characters (R7RS 6.6)
        "char?": char_p,
        "char=?": char_eq_p,
        "char<?": char_lt_p,
        "char>?": char_gt_p,
        "char<=?": char_le_p,
        "char>=?": char_ge_p,
        "char-ci=?": char_ci_eq_p,
        "char-ci<?": char_ci_lt_p,
        "char-ci>?": char_ci_gt_p,
        "char-ci<=?": char_ci_le_p,
        "char-ci>=?": char_ci_ge_p,
        "char-alphabetic?": char_alphabetic_p,
        "char-numeric?": char_numeric_p,
        "char-whitespace?": char_whitespace_p,
        "char-upper-case?": char_upper_case_p,
        "char-lower-case?": char_lower_case_p,
        "digit-value": digit_value,
        "char->integer": char_to_integer,
        "integer->char": integer_to_char,
        "char-upcase": char_upcase,
        "char-downcase": char_downcase,
        "char-foldcase": char_foldcase,
        # Strings (R7RS 6.7)
        "string?": string_p,
        "make-string": make_string,
        "string": string_constructor,
        "string-length": string_length,
        "string-ref": string_ref,
        "string-set!": string_set_bang,
        "string=?": string_eq_p,
        "string<?": string_lt_p,
        "string>?": string_gt_p,
        "string<=?": string_le_p,
        "string>=?": string_ge_p,
        "string-ci=?": string_ci_eq_p,
        "string-ci<?": string_ci_lt_p,
        "string-ci>?": string_ci_gt_p,
        "string-ci<=?": string_ci_le_p,
        "string-ci>=?": string_ci_ge_p,
        "substring": substring,
        "string-copy": string_copy,
        "string-copy!": string_copy_bang,
        "string-fill!": string_fill_bang,
        "string-append": string_append,
        "string->list": string_to_list,
        "list->string": list_to_string,
        "string->vector": string_to_vector,
        "vector->string": vector_to_string,
        "string-map": string_map,
        "string-for-each": string_for_each,
        "string-upcase": string_upcase,
        "string-downcase": string_downcase,
        "string-foldcase": string_foldcase,
        # Equality and Booleans
        "eq?": prim_eq_p,
        "eqv?": prim_eqv_p,
        "equal?": prim_equal_p,
        "boolean?": prim_boolean_p,
        "boolean=?": prim_boolean_eq,
        "not": prim_not,
        # Arithmetic & Numeric comparison (R7RS 6.2)
        "+": prim_add,
        "-": prim_sub,
        "*": prim_mul,
        "/": num_div,
        "=": num_eq,
        "<": num_lt,
        ">": num_gt,
        "<=": num_le,
        ">=": num_ge,
        "zero?": zero_p,
        "positive?": positive_p,
        "negative?": negative_p,
        "odd?": odd_p,
        "even?": even_p,
        "number?": number_p,
        "complex?": complex_p,
        "real?": real_p,
        "rational?": rational_p,
        "integer?": integer_p,
        "exact?": exact_p,
        "inexact?": inexact_p,
        "exact-integer?": exact_integer_p,
        "exact-integer-sqrt": exact_integer_sqrt,
        "make-rectangular": make_rectangular,
        "make-polar": make_polar,
        "real-part": real_part,
        "imag-part": imag_part,
        "magnitude": num_magnitude,
        "angle": num_angle,
        "finite?": finite_p,
        "infinite?": infinite_p,
        "nan?": nan_p,
        "max": num_max,
        "min": num_min,
        "abs": num_abs,
        "gcd": num_gcd,
        "lcm": num_lcm,
        "floor": num_floor,
        "ceiling": num_ceiling,
        "truncate": num_truncate,
        "round": num_round,
        "floor/": floor_div,
        "floor-quotient": floor_quotient,
        "floor-remainder": floor_remainder,
        "truncate/": truncate_div,
        "truncate-quotient": truncate_quotient,
        "truncate-remainder": truncate_remainder,
        "quotient": truncate_quotient,
        "remainder": truncate_remainder,
        "modulo": num_modulo,
        "exact": num_exact,
        "inexact": num_inexact,
        "exact->inexact": num_inexact,
        "inexact->exact": num_exact,
        "square": num_square,
        "sqrt": num_sqrt,
        "expt": num_expt,
        "exp": num_exp,
        "log": num_log,
        "sin": num_sin,
        "cos": num_cos,
        "tan": num_tan,
        "asin": num_asin,
        "acos": num_acos,
        "atan": num_atan,
        "number->string": number_to_string,
        "string->number": string_to_number,
        # Vectors (R7RS)
        "vector?": prim_vector_p,
        "make-vector": prim_make_vector,
        "vector": prim_vector,
        "vector-ref": prim_vector_ref,
        "vector-set!": prim_vector_set_bang,
        "vector-length": prim_vector_length,
        "vector->list": prim_vector_to_list,
        "list->vector": prim_list_to_vector,
        "vector-copy": prim_vector_copy,
        "vector-copy!": prim_vector_copy_bang,
        "vector-fill!": prim_vector_fill_bang,
        "vector-append": prim_vector_append,
        "vector-map": prim_vector_map,
        "vector-for-each": prim_vector_for_each,
        # Multiple Values (R7RS)
        "values": prim_values,
        "call-with-values": prim_call_with_values,
        # Continuations & Dynamic Control (R7RS)
        "call/cc": prim_call_cc,
        "call-with-current-continuation": prim_call_cc,
        "dynamic-wind": prim_dynamic_wind,
        # Parameters (R7RS)
        "make-parameter": prim_make_parameter,
        "parameter?": prim_parameter_p,
        # Procedure Application (R7RS 6.4)
        "apply": prim_apply,
        # Delayed Evaluation (R7RS 4.2.5 & 6.10)
        "promise?": prim_promise_p,
        "make-promise": prim_make_promise,
        "__make-promise-from-thunk": prim_make_promise_from_thunk,
        "force": prim_force,
        # Records (R7RS 5.5 & 6.x)
        "make-record-type": prim_make_record_type,
        "record-type?": prim_record_type_p,
        "record?": prim_record_p,
        "record-type": prim_record_type,
        "record-type-name": prim_record_type_name,
        "record-type-field-names": prim_record_type_field_names,
        "make-record": prim_make_record,
        "record-ref": prim_record_ref,
        "record-set!": prim_record_set_bang,
        "record-predicate": prim_record_predicate,
        "record-accessor": prim_record_accessor,
        "record-modifier": prim_record_modifier,
        "record-constructor": prim_record_constructor,
        # Exceptions & Conditions (R7RS 6.11)
        "raise": prim_raise,
        "raise-continuable": prim_raise,
        "with-exception-handler": prim_with_exception_handler,
        "error": prim_error,
        "syntax-error": prim_syntax_error,
        "error-object?": prim_error_object_p,
        "error-object-message": prim_error_object_message,
        "error-object-irritants": prim_error_object_irritants,
        "read-error?": prim_read_error_p,
        "file-error?": prim_file_error_p,
        "read-error": prim_read_error,
        "file-error": prim_file_error,
        # Ports and I/O (R7RS)
        "port?": port_mod.port_p,
        "input-port?": port_mod.input_port_p,
        "output-port?": port_mod.output_port_p,
        "textual-port?": port_mod.textual_port_p,
        "binary-port?": port_mod.binary_port_p,
        "port-open?": port_mod.port_open_p,
        "input-port-open?": port_mod.input_port_open_p,
        "output-port-open?": port_mod.output_port_open_p,
        "close-port": port_mod.close_port,
        "close-input-port": port_mod.close_input_port,
        "close-output-port": port_mod.close_output_port,
        "current-input-port": port_mod.get_current_input_port,
        "current-output-port": port_mod.get_current_output_port,
        "current-error-port": port_mod.get_current_error_port,
        "open-input-string": port_mod.open_input_string,
        "open-output-string": port_mod.open_output_string,
        "get-output-string": port_mod.get_output_string,
        "open-input-file": port_mod.open_input_file,
        "open-output-file": port_mod.open_output_file,
        "call-with-port": port_mod.call_with_port,
        "call-with-input-file": port_mod.call_with_input_file,
        "call-with-output-file": port_mod.call_with_output_file,
        "with-input-from-file": port_mod.with_input_from_file,
        "with-output-to-file": port_mod.with_output_to_file,
        "read": prim_read,
        "read-char": prim_read_char,
        "peek-char": prim_peek_char,
        "read-line": prim_read_line,
        "read-string": prim_read_string,
        "char-ready?": prim_char_ready_p,
        "write-char": prim_write_char,
        "write-string": prim_write_string,
        "newline": prim_newline,
        "flush-output-port": prim_flush_output_port,
        "display": prim_display,
        "write": prim_write,
        "write-simple": prim_write_simple,
        "write-shared": prim_write_shared,
        "eof-object": prim_eof_object,
        "eof-object?": prim_eof_object_p,
        # Bytevectors (R7RS 6.9)
        "bytevector?": prim_bytevector_p,
        "make-bytevector": prim_make_bytevector,
        "bytevector": prim_bytevector,
        "bytevector-length": prim_bytevector_length,
        "bytevector-u8-ref": prim_bytevector_u8_ref,
        "bytevector-u8-set!": prim_bytevector_u8_set_bang,
        "bytevector-copy": prim_bytevector_copy,
        "bytevector-copy!": prim_bytevector_copy_bang,
        "bytevector-append": prim_bytevector_append,
        "utf8->string": prim_utf8_to_string,
        "string->utf8": prim_string_to_utf8,
        # Binary Ports (R7RS 6.13)
        "open-binary-input-file": port_mod.open_binary_input_file,
        "open-binary-output-file": port_mod.open_binary_output_file,
        "open-input-bytevector": port_mod.open_input_bytevector,
        "open-output-bytevector": port_mod.open_output_bytevector,
        "get-output-bytevector": port_mod.get_output_bytevector,
        "read-u8": port_mod.read_u8,
        "peek-u8": port_mod.peek_u8,
        "u8-ready?": port_mod.u8_ready_p,
        "write-u8": port_mod.write_u8,
        "read-bytevector": prim_read_bytevector,
        "read-bytevector!": prim_read_bytevector_bang,
        "write-bytevector": prim_write_bytevector,
        "load": prim_load,
        # System & Time (R7RS 6.14, (scheme time))
        "current-second": prim_current_second,
        "current-jiffy": prim_current_jiffy,
        "jiffies-per-second": prim_jiffies_per_second,
        # Process Context (R7RS 6.14, (scheme process-context))
        "get-environment-variable": prim_get_environment_variable,
        "get-environment-variables": prim_get_environment_variables,
        "command-line": prim_command_line,
        "exit": prim_exit,
        "emergency-exit": prim_emergency_exit,
        # Python Zero-Copy & Interop
        "sequence-view": prim_sequence_view,
        "py-import": prim_py_import,
        "py-call": prim_py_call,
        "py-get": prim_py_get,
        "py-set!": prim_py_set_bang,
        "py-eval": prim_py_eval,
    }

    for name, fn in primitives.items():
        sym = Symbol.intern(name)
        env.define(sym, Primitive(name, fn))

    if preload_stdlib:
        stdlib_path = Path(__file__).parent / "stdlib" / "base.ilisp"
        if stdlib_path.exists():
            prim_load(str(stdlib_path))

    return env

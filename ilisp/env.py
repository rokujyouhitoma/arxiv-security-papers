"""Lexical Environment and Core Primitives for Kernel ILISP.

This module implements nested lexical scopes, variable binding, Cell boxing,
and standard R7RS-small core primitives plus Python zero-copy interop.
"""

from __future__ import annotations

import importlib
from pathlib import Path
from typing import Any, Callable, Dict, Optional, Sequence, Union

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
from ilisp.types import (
    NIL,
    Bytevector,
    Cell,
    Char,
    Cons,
    Continuation,
    EscapeContinuation,
    MutableString,
    Parameter,
    Primitive,
    Procedure,
    SchemeException,
    SequenceView,
    Symbol,
    Values,
    Vector,
    car,
    cdr,
    is_null,
    is_pair,
    is_parameter,
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

    def prim_pair_p(x: Any) -> bool:
        return is_pair(x)

    def prim_null_p(x: Any) -> bool:
        return is_null(x)

    def prim_list(*args: Any) -> Any:
        return to_lisp_list(args)

    # --- 2. Symbol & String Primitives ---
    def prim_symbol_p(x: Any) -> bool:
        return isinstance(x, Symbol)

    def prim_symbol_to_string(s: Symbol) -> str:
        if not isinstance(s, Symbol):
            raise TypeError(f"symbol->string expected symbol, got {s!r}")
        return s.name

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
        if isinstance(a, (int, float, str, bool, Char)) and isinstance(
            b, (int, float, str, bool, Char)
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
        return False

    def prim_boolean_p(x: Any) -> bool:
        return isinstance(x, bool)

    def prim_not(x: Any) -> bool:
        # In Scheme, only #f is false. Everything else (including 0 and '()) is truthy!
        return x is False

    # --- 4. Arithmetic & Comparison Primitives ---
    def prim_add(*nums: Union[int, float]) -> Union[int, float]:
        total: Union[int, float] = 0
        for n in nums:
            total += n
        return total

    def prim_sub(
        first: Union[int, float], *rest: Union[int, float]
    ) -> Union[int, float]:
        if not rest:
            return -first
        total = first
        for n in rest:
            total -= n
        return total

    def prim_mul(*nums: Union[int, float]) -> Union[int, float]:
        prod: Union[int, float] = 1
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

    def prim_write_string(
        s: str, port: Optional[port_mod.TextualOutputPort] = None
    ) -> None:
        port_mod.write_string(s, port)

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

    # Exceptions & Conditions (R7RS)
    def prim_raise(datum: Any) -> Any:
        raise SchemeException(datum)

    def prim_with_exception_handler(handler: Any, thunk: Any) -> Any:
        from ilisp.evaluator import _apply_procedure

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
        except Exception as py_err:
            if isinstance(handler, Procedure):
                return _apply_procedure(handler, [str(py_err)])
            elif callable(handler):
                return handler(str(py_err))
            raise

    def prim_error(msg: str, *args: Any) -> Any:
        err_obj = Cons(Symbol.intern("error"), Cons(msg, to_lisp_list(args)))
        raise SchemeException(err_obj)

    # Register all primitives
    primitives: Dict[str, Callable[..., Any]] = {
        # Pairs and Lists
        "cons": prim_cons,
        "car": prim_car,
        "cdr": prim_cdr,
        "pair?": prim_pair_p,
        "null?": prim_null_p,
        "list": prim_list,
        # Symbols
        "symbol?": prim_symbol_p,
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
        "not": prim_not,
        # Arithmetic & Numeric comparison
        "+": prim_add,
        "-": prim_sub,
        "*": prim_mul,
        "quotient": prim_quotient,
        "remainder": prim_remainder,
        "=": prim_num_eq,
        "<": prim_num_lt,
        ">": prim_num_gt,
        "<=": prim_num_le,
        ">=": prim_num_ge,
        # Vectors (R7RS)
        "vector?": prim_vector_p,
        "make-vector": prim_make_vector,
        "vector": prim_vector,
        "vector-ref": prim_vector_ref,
        "vector-set!": prim_vector_set_bang,
        "vector-length": prim_vector_length,
        "vector->list": prim_vector_to_list,
        "list->vector": prim_list_to_vector,
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
        # Exceptions (R7RS)
        "raise": prim_raise,
        "raise-continuable": prim_raise,
        "with-exception-handler": prim_with_exception_handler,
        "error": prim_error,
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
        "read-bytevector": port_mod.read_bytevector,
        "read-bytevector!": port_mod.read_bytevector_bang,
        "write-bytevector": port_mod.write_bytevector,
        "load": prim_load,
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

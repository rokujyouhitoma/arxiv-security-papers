"""ALisp SafePyProxy Subsystem.

Provides transparent proxy wrapper preventing reflection, metaclass inspection,
and sandbox escapes through Python dunder attribute traversal.
"""

from __future__ import annotations

from typing import Any, Iterator, List, Set, Tuple

from alisp.caps.base import AccessDeniedException

# Comprehensive list of forbidden reflection, code object, and metaclass attributes
FORBIDDEN_METADATA_ATTRIBUTES: Set[str] = {
    # Metaclass & class traversal
    "__class__",
    "__bases__",
    "__base__",
    "__mro__",
    "__subclasses__",
    # Global environment & namespaces
    "__globals__",
    "__builtins__",
    "__dict__",
    "__module__",
    "__qualname__",
    "__name__",
    "__doc__",
    # Code execution & bytecode introspection
    "__code__",
    "__closure__",
    "__annotations__",
    "__wrapped__",
    "__loader__",
    "__spec__",
    "__file__",
    "__cached__",
    # Object lifecycle & deserialization hooks
    "__init__",
    "__new__",
    "__reduce__",
    "__reduce_ex__",
    "__getstate__",
    "__setstate__",
    # Introspection internals
    "__getattribute__",
    "__self__",
    "__func__",
    "__import__",
    # Generator & frame introspection
    "gi_frame",
    "gi_code",
    "cr_frame",
    "cr_code",
    "ag_frame",
    "ag_code",
    "f_globals",
    "f_builtins",
    "f_locals",
    "f_code",
    "f_back",
    "f_trace",
    "tb_frame",
    "tb_next",
}

# Permitted internal/standard dunder attributes on the proxy instance itself
_SAFE_PROXY_INTERNAL_SLOTS: Set[str] = {
    "_target",
    "_is_callable",
}


class SafePyProxy:
    """Transparent proxy wrapper for Python objects enforcing physical integrity.

    Hard-denies any access to reflection, code objects, metaclass hierarchy,
    or dunder attributes to prevent sandbox escapes and remote code execution.
    """

    __slots__ = ("_target", "_is_callable")

    def __init__(self, target: Any) -> None:
        object.__setattr__(self, "_target", target)
        object.__setattr__(self, "_is_callable", callable(target))

    def __getattribute__(self, name: str) -> Any:
        if name in _SAFE_PROXY_INTERNAL_SLOTS:
            return object.__getattribute__(self, name)

        # Hard Deny on any dunder or forbidden metadata inspection
        if (
            name.startswith("__") and name.endswith("__")
        ) or name in FORBIDDEN_METADATA_ATTRIBUTES:
            raise AccessDeniedException(
                f"SafePyProxy: Access to forbidden reflection attribute {name!r} is strictly denied"
            )

        target = object.__getattribute__(self, "_target")
        try:
            val = getattr(target, name)
        except AttributeError as e:
            raise AttributeError(
                f"SafePyProxy: Target object has no attribute {name!r}"
            ) from e

        return wrap_safe_proxy(val)

    def __setattr__(self, name: str, value: Any) -> None:
        if name in _SAFE_PROXY_INTERNAL_SLOTS:
            object.__setattr__(self, name, value)
            return

        if (
            name.startswith("__") and name.endswith("__")
        ) or name in FORBIDDEN_METADATA_ATTRIBUTES:
            raise AccessDeniedException(
                f"SafePyProxy: Mutation of forbidden reflection attribute {name!r} is strictly denied"
            )

        target = object.__getattribute__(self, "_target")
        setattr(target, name, unwrap_safe_proxy(value))

    def __delattr__(self, name: str) -> None:
        if (
            name.startswith("__") and name.endswith("__")
        ) or name in FORBIDDEN_METADATA_ATTRIBUTES:
            raise AccessDeniedException(
                f"SafePyProxy: Deletion of forbidden reflection attribute {name!r} is strictly denied"
            )

        target = object.__getattribute__(self, "_target")
        delattr(target, name)

    def __call__(self, *args: Any, **kwargs: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        if not object.__getattribute__(self, "_is_callable"):
            raise TypeError(
                f"SafePyProxy: Wrapped object {type(target).__name__!r} is not callable"
            )

        unwrapped_args = [unwrap_safe_proxy(a) for a in args]
        unwrapped_kwargs = {k: unwrap_safe_proxy(v) for k, v in kwargs.items()}
        res = target(*unwrapped_args, **unwrapped_kwargs)
        return wrap_safe_proxy(res)

    def __getitem__(self, key: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        unwrapped_key = unwrap_safe_proxy(key)
        res = target[unwrapped_key]
        return wrap_safe_proxy(res)

    def __setitem__(self, key: Any, value: Any) -> None:
        target = object.__getattribute__(self, "_target")
        target[unwrap_safe_proxy(key)] = unwrap_safe_proxy(value)

    def __delitem__(self, key: Any) -> None:
        target = object.__getattribute__(self, "_target")
        del target[unwrap_safe_proxy(key)]

    def __iter__(self) -> Iterator[Any]:
        target = object.__getattribute__(self, "_target")
        for item in target:
            yield wrap_safe_proxy(item)

    def __next__(self) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(next(target))

    def __len__(self) -> int:
        target = object.__getattribute__(self, "_target")
        return len(target)

    def __contains__(self, item: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return unwrap_safe_proxy(item) in target

    def __str__(self) -> str:
        target = object.__getattribute__(self, "_target")
        return str(target)

    def __repr__(self) -> str:
        target = object.__getattribute__(self, "_target")
        return f"#<SafePyProxy for {type(target).__name__}>"

    def __bool__(self) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target)

    def __dir__(self) -> List[str]:
        target = object.__getattribute__(self, "_target")
        all_attrs = dir(target)
        # Filter out all dunders and forbidden metadata attributes
        return [
            attr
            for attr in all_attrs
            if not (attr.startswith("__") and attr.endswith("__"))
            and attr not in FORBIDDEN_METADATA_ATTRIBUTES
        ]

    # Comparison delegates
    def __eq__(self, other: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target == unwrap_safe_proxy(other))

    def __ne__(self, other: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target != unwrap_safe_proxy(other))

    def __lt__(self, other: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target < unwrap_safe_proxy(other))

    def __le__(self, other: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target <= unwrap_safe_proxy(other))

    def __gt__(self, other: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target > unwrap_safe_proxy(other))

    def __ge__(self, other: Any) -> bool:
        target = object.__getattribute__(self, "_target")
        return bool(target >= unwrap_safe_proxy(other))

    def __hash__(self) -> int:
        target = object.__getattribute__(self, "_target")
        return hash(target)

    # Arithmetic delegates
    def __add__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target + unwrap_safe_proxy(other))

    def __radd__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(unwrap_safe_proxy(other) + target)

    def __sub__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target - unwrap_safe_proxy(other))

    def __mul__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target * unwrap_safe_proxy(other))

    def __truediv__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target / unwrap_safe_proxy(other))

    def __floordiv__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target // unwrap_safe_proxy(other))

    def __mod__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target % unwrap_safe_proxy(other))

    def __pow__(self, other: Any) -> Any:
        target = object.__getattribute__(self, "_target")
        return wrap_safe_proxy(target ** unwrap_safe_proxy(other))


def is_safe_proxy(val: Any) -> bool:
    """Return True if val is an instance of SafePyProxy."""
    return isinstance(val, SafePyProxy)


def unwrap_safe_proxy(val: Any) -> Any:
    """Extract raw underlying target from SafePyProxy if wrapped, else return val unchanged."""
    if isinstance(val, SafePyProxy):
        return object.__getattribute__(val, "_target")
    return val


# Primitive types that do not require proxy wrapping
_PRIMITIVE_TYPES: Tuple[type, ...] = (
    int,
    float,
    complex,
    bool,
    str,
    bytes,
    bytearray,
    type(None),
)


def wrap_safe_proxy(val: Any) -> Any:
    """Wrap a Python object in SafePyProxy unless it is already a primitive or Lisp value."""
    if val is None or isinstance(val, _PRIMITIVE_TYPES):
        return val

    if isinstance(val, SafePyProxy):
        return val

    # Avoid wrapping native ILisp types
    try:
        from ilisp.types import (
            NIL,
            Bytevector,
            Cell,
            Cons,
            NilType,
            Primitive,
            Procedure,
            Symbol,
            Vector,
        )

        if val is NIL or isinstance(
            val, (Symbol, Cons, NilType, Cell, Primitive, Procedure, Bytevector, Vector)
        ):
            return val
    except ImportError:
        pass

    return SafePyProxy(val)


# Dangerous system modules prohibited in sandboxed ALisp execution
DANGEROUS_SYSTEM_MODULES: Set[str] = {
    "os",
    "sys",
    "subprocess",
    "shutil",
    "ctypes",
    "socket",
    "pty",
    "importlib",
    "posix",
    "nt",
    "_thread",
    "threading",
    "multiprocessing",
    "signal",
    "builtins",
    "inspect",
    "gc",
    "code",
    "codeop",
}


def install_sandboxed_py_primitives(env: Any) -> None:
    """Install safe Python interop primitives into an ILisp/ALisp Environment."""
    import importlib

    from ilisp.types import (
        ErrorObject,
        Primitive,
        SchemeException,
        Symbol,
        is_pair,
        to_lisp_list,
        to_py_list,
    )

    def safe_py_import(mod_name: Any) -> Any:
        name = mod_name.name if isinstance(mod_name, Symbol) else str(mod_name)
        root_module = name.split(".")[0]
        if root_module in DANGEROUS_SYSTEM_MODULES:
            raise AccessDeniedException(
                f"SafePyProxy: Import of dangerous system module {name!r} is strictly prohibited"
            )
        try:
            mod = importlib.import_module(name)
            return wrap_safe_proxy(mod)
        except Exception as e:
            err = ErrorObject(
                f"import-python: failed to import module {name!r}: {e}",
                to_lisp_list([name]),
                kind="import",
            )
            raise SchemeException(err) from e

    def safe_py_call(obj: Any, method_or_arg: Any, *args: Any) -> Any:
        raw_obj = unwrap_safe_proxy(obj)
        # Check if direct call
        is_direct = callable(raw_obj) and (
            not isinstance(method_or_arg, (Symbol, str))
            or not hasattr(
                raw_obj,
                (
                    method_or_arg.name
                    if isinstance(method_or_arg, Symbol)
                    else str(method_or_arg)
                ),
            )
        )
        if is_direct:
            all_args = [method_or_arg, *args]
            unwrapped_args = [
                to_py_list(arg) if is_pair(arg) else unwrap_safe_proxy(arg)
                for arg in all_args
            ]
            res = raw_obj(*unwrapped_args)
            return wrap_safe_proxy(res)

        method_name = (
            method_or_arg.name
            if isinstance(method_or_arg, Symbol)
            else str(method_or_arg)
        )
        if (
            method_name.startswith("__") and method_name.endswith("__")
        ) or method_name in FORBIDDEN_METADATA_ATTRIBUTES:
            raise AccessDeniedException(
                f"SafePyProxy: Invocation of forbidden reflection method {method_name!r} is strictly denied"
            )

        fn = getattr(raw_obj, method_name)
        unwrapped_args = [
            to_py_list(arg) if is_pair(arg) else unwrap_safe_proxy(arg) for arg in args
        ]
        res = fn(*unwrapped_args)
        return wrap_safe_proxy(res)

    def safe_py_get(obj: Any, attr: Any) -> Any:
        attr_name = attr.name if isinstance(attr, Symbol) else str(attr)
        if (
            attr_name.startswith("__") and attr_name.endswith("__")
        ) or attr_name in FORBIDDEN_METADATA_ATTRIBUTES:
            raise AccessDeniedException(
                f"SafePyProxy: Access to forbidden reflection attribute {attr_name!r} is strictly denied"
            )

        raw_obj = unwrap_safe_proxy(obj)
        if isinstance(raw_obj, dict):
            if attr_name not in raw_obj:
                err = ErrorObject(
                    f"py-get: key {attr_name!r} not found in dict",
                    to_lisp_list([attr_name]),
                    kind="import",
                )
                raise SchemeException(err)
            return wrap_safe_proxy(raw_obj.get(attr_name))

        if not hasattr(raw_obj, attr_name):
            err = ErrorObject(
                f"py-get: object {raw_obj!r} has no attribute {attr_name!r}",
                to_lisp_list([attr_name]),
                kind="import",
            )
            raise SchemeException(err)

        return wrap_safe_proxy(getattr(raw_obj, attr_name))

    def safe_py_set_bang(obj: Any, attr: Any, val: Any) -> None:
        attr_name = attr.name if isinstance(attr, Symbol) else str(attr)
        if (
            attr_name.startswith("__") and attr_name.endswith("__")
        ) or attr_name in FORBIDDEN_METADATA_ATTRIBUTES:
            raise AccessDeniedException(
                f"SafePyProxy: Mutation of forbidden reflection attribute {attr_name!r} is strictly denied"
            )

        raw_obj = unwrap_safe_proxy(obj)
        unwrapped_val = unwrap_safe_proxy(val)
        if isinstance(raw_obj, dict):
            raw_obj[attr_name] = unwrapped_val
        else:
            setattr(raw_obj, attr_name, unwrapped_val)

    def safe_py_eval(expr_str: Any) -> Any:
        raise AccessDeniedException(
            "SafePyProxy: py-eval is strictly prohibited in sandboxed ALisp execution"
        )

    def safe_dot(obj: Any, member_spec: Any, *args: Any) -> Any:
        if isinstance(member_spec, Symbol):
            spec_name = member_spec.name
            if spec_name.startswith("-") and len(spec_name) > 1:
                attr_name = spec_name[1:]
                if not args:
                    return safe_py_get(obj, attr_name)
                elif len(args) == 1:
                    return safe_py_set_bang(obj, attr_name, args[0])
                else:
                    raise TypeError(
                        f"'.' attribute access takes 1 or 2 arguments, got {len(args) + 1}"
                    )
            return safe_py_call(obj, spec_name, *args)
        elif is_pair(member_spec):
            from ilisp.types import car, cdr

            method_sym = car(member_spec)
            method_name = (
                method_sym.name if isinstance(method_sym, Symbol) else str(method_sym)
            )
            all_args = to_py_list(cdr(member_spec)) + list(args)
            return safe_py_call(obj, method_name, *all_args)
        else:
            return safe_py_call(obj, member_spec, *args)

    # Register sandboxed primitives
    env.define(Symbol.intern("py-import"), Primitive("py-import", safe_py_import))
    env.define(Symbol.intern("py-call"), Primitive("py-call", safe_py_call))
    env.define(Symbol.intern("py-get"), Primitive("py-get", safe_py_get))
    env.define(Symbol.intern("py-set!"), Primitive("py-set!", safe_py_set_bang))
    env.define(Symbol.intern("py-eval"), Primitive("py-eval", safe_py_eval))
    env.define(Symbol.intern("."), Primitive(".", safe_dot))

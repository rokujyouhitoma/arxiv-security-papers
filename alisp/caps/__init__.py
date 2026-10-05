"""ALisp Object-Capability (OCaps) Subsystem.

Provides unforgeable Capability tokens, authority attenuation, with-caps macro,
and sandboxed primitives for strict isolation of destructive I/O.
"""

from __future__ import annotations

from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any, Dict, Iterator, List, Optional, Sequence

from alisp.caps.base import AccessDeniedException, Capability, CapabilityError
from alisp.caps.fs import FileSystemCapability
from alisp.caps.net import NetworkCapability
from alisp.caps.port import (
    ManagedBinaryInputPort,
    ManagedBinaryOutputPort,
    ManagedPortMixin,
    ManagedTextualInputPort,
    ManagedTextualOutputPort,
    PortQuotaExceededException,
    make_loopback_binary_port,
    make_loopback_textual_port,
    wrap_managed_port,
)
from alisp.caps.taint import (
    TaintedValue,
    TaintLeakViolationException,
    check_sink,
    is_tainted,
    taint,
    untaint,
)
from ilisp.env import Environment
from ilisp.evaluator import _apply_procedure
from ilisp.types import (
    NIL,
    Cons,
    Primitive,
    Procedure,
    Symbol,
    car,
    cdr,
    is_null,
    is_pair,
    to_lisp_list,
    to_py_list,
)

_active_caps_var: ContextVar[Dict[str, Capability]] = ContextVar(
    "_active_caps_var", default={}
)


def get_active_capabilities() -> Dict[str, Capability]:
    """Retrieve currently active capability tokens in the current execution context."""
    return _active_caps_var.get()


def get_active_capability(name: str) -> Optional[Capability]:
    """Retrieve an active capability token by name (e.g. 'fs-cap', 'net-cap')."""
    return _active_caps_var.get().get(name)


@contextmanager
def with_capabilities(caps: Sequence[Capability]) -> Iterator[Dict[str, Capability]]:
    """Context manager setting active capabilities for the duration of the scope."""
    parent = _active_caps_var.get()
    new_caps = dict(parent)
    for cap in caps:
        if isinstance(cap, Capability):
            new_caps[cap.name] = cap
        else:
            raise TypeError(f"Expected Capability object, got {cap!r}")
    token = _active_caps_var.set(new_caps)
    try:
        yield new_caps
    finally:
        _active_caps_var.reset(token)


class WithCapsTransformer:
    """Macro transformer for (with-caps (<cap-bindings>...) body...).

    Supports two syntax forms:
    Form 1: Variable binding
      (with-caps ((fs (make-fs-cap ...)) (net (make-net-cap ...)))
        (expr ...))
      Desugars to:
        (let ((fs (make-fs-cap ...)) (net (make-net-cap ...)))
          (%with-caps (list fs net) (lambda () (begin (expr ...))))))

    Form 2: Anonymous capabilities list
      (with-caps (cap1 cap2)
        (expr ...))
      Desugars to:
        (%with-caps (list cap1 cap2) (lambda () (begin (expr ...))))
    """

    def transform(self, expr: Any, env: Any) -> Any:
        args = cdr(expr)
        if not is_pair(args):
            raise SyntaxError(
                "with-caps requires capability bindings and at least one body expression: "
                "(with-caps (<bindings>...) body...)"
            )
        bindings = car(args)
        body = cdr(args)
        if not is_pair(body):
            raise SyntaxError("with-caps requires at least one body expression")

        # Construct: (lambda () (begin body...))
        begin_form = Cons(Symbol.intern("begin"), body)
        lambda_form = Cons(Symbol.intern("lambda"), Cons(NIL, Cons(begin_form, NIL)))

        # Analyze bindings form
        binding_list = to_py_list(bindings)
        is_var_binding = all(is_pair(b) and is_pair(cdr(b)) for b in binding_list)

        if is_var_binding and len(binding_list) > 0:
            var_names = [car(b) for b in binding_list]
            list_call = Cons(
                Symbol.intern("list"),
                to_lisp_list(var_names),
            )
            # (%with-caps (list var...) lambda_form)
            with_caps_call = Cons(
                Symbol.intern("%with-caps"),
                Cons(list_call, Cons(lambda_form, NIL)),
            )
            # (let ((v1 e1) ...) with_caps_call)
            return Cons(
                Symbol.intern("let"),
                Cons(bindings, Cons(with_caps_call, NIL)),
            )
        else:
            list_call = Cons(Symbol.intern("list"), bindings)
            return Cons(
                Symbol.intern("%with-caps"),
                Cons(list_call, Cons(lambda_form, NIL)),
            )


def make_with_caps_primitive() -> Primitive:
    """Create the %with-caps primitive executing a thunk under activated capabilities."""

    def _prim_with_caps(caps_obj: Any, thunk: Any) -> Any:
        caps_list: List[Capability] = []
        if isinstance(caps_obj, (list, tuple)):
            py_caps = list(caps_obj)
        elif is_pair(caps_obj) or is_null(caps_obj):
            py_caps = to_py_list(caps_obj)
        elif isinstance(caps_obj, Capability):
            py_caps = [caps_obj]
        else:
            raise TypeError(
                f"with-caps expected capability or list of capabilities, got {caps_obj!r}"
            )

        for c in py_caps:
            if not isinstance(c, Capability):
                raise TypeError(
                    f"with-caps elements must be Capability instances, got {c!r}"
                )
            caps_list.append(c)

        with with_capabilities(caps_list):
            if isinstance(thunk, Procedure):
                return _apply_procedure(thunk, [])
            elif callable(thunk):
                return thunk()
            else:
                raise TypeError(f"with-caps expected procedure thunk, got {thunk!r}")

    return Primitive("%with-caps", _prim_with_caps)


def make_fs_cap_primitive() -> Primitive:
    """Create (make-fs-cap allowed-read allowed-write [loopback] [budget]) primitive."""

    def _prim_make_fs_cap(*args: Any) -> FileSystemCapability:
        read_paths: Optional[List[str]] = None
        write_paths: Optional[List[str]] = None
        loopback: bool = True
        budget: int = 1024 * 1024

        if len(args) >= 1:
            raw_read = args[0]
            if isinstance(raw_read, str):
                read_paths = [raw_read]
            elif isinstance(raw_read, (list, tuple)):
                read_paths = list(raw_read)
            elif is_pair(raw_read) or is_null(raw_read):
                read_paths = to_py_list(raw_read)
        if len(args) >= 2:
            raw_write = args[1]
            if isinstance(raw_write, str):
                write_paths = [raw_write]
            elif isinstance(raw_write, (list, tuple)):
                write_paths = list(raw_write)
            elif is_pair(raw_write) or is_null(raw_write):
                write_paths = to_py_list(raw_write)
        if len(args) >= 3:
            loopback = bool(args[2])
        if len(args) >= 4:
            budget = int(args[3])

        return FileSystemCapability(
            allowed_read_paths=read_paths,
            allowed_write_paths=write_paths,
            loopback_unauthorized_writes=loopback,
            byte_budget=budget,
        )

    return Primitive("make-fs-cap", _prim_make_fs_cap)


def make_net_cap_primitive() -> Primitive:
    """Create (make-net-cap allowed-hosts [allowed-methods] [budget]) primitive."""

    def _prim_make_net_cap(*args: Any) -> NetworkCapability:
        hosts: Optional[List[str]] = None
        methods: Optional[List[str]] = None
        budget: int = 1024 * 1024

        if len(args) >= 1:
            raw_hosts = args[0]
            if isinstance(raw_hosts, str):
                hosts = [raw_hosts]
            elif isinstance(raw_hosts, (list, tuple)):
                hosts = list(raw_hosts)
            elif is_pair(raw_hosts) or is_null(raw_hosts):
                hosts = to_py_list(raw_hosts)
        if len(args) >= 2:
            raw_methods = args[1]
            if isinstance(raw_methods, str):
                methods = [raw_methods]
            elif isinstance(raw_methods, (list, tuple)):
                methods = list(raw_methods)
            elif is_pair(raw_methods) or is_null(raw_methods):
                methods = to_py_list(raw_methods)
        if len(args) >= 3:
            budget = int(args[3])

        return NetworkCapability(
            allowed_hosts=hosts,
            allowed_methods=methods,
            byte_budget=budget,
        )

    return Primitive("make-net-cap", _prim_make_net_cap)


def make_attenuate_cap_primitive() -> Primitive:
    """Create (attenuate-cap cap ...) primitive enforcing authority decay."""

    def _prim_attenuate(cap: Any, *args: Any) -> Capability:
        if not isinstance(cap, Capability):
            raise TypeError(f"attenuate-cap requires Capability instance, got {cap!r}")
        if isinstance(cap, FileSystemCapability):
            read_paths = (
                to_py_list(args[0]) if len(args) >= 1 and args[0] is not None else None
            )
            write_paths = (
                to_py_list(args[1]) if len(args) >= 2 and args[1] is not None else None
            )
            loopback = args[2] if len(args) >= 3 else None
            budget = args[3] if len(args) >= 4 else None
            return cap.attenuate(
                allowed_read_paths=read_paths,
                allowed_write_paths=write_paths,
                loopback_unauthorized_writes=loopback,
                byte_budget=budget,
            )
        elif isinstance(cap, NetworkCapability):
            hosts = (
                to_py_list(args[0]) if len(args) >= 1 and args[0] is not None else None
            )
            methods = (
                to_py_list(args[1]) if len(args) >= 2 and args[1] is not None else None
            )
            budget = args[2] if len(args) >= 3 else None
            return cap.attenuate(
                allowed_hosts=hosts,
                allowed_methods=methods,
                byte_budget=budget,
            )
        else:
            raise TypeError(f"Unsupported capability type: {type(cap)}")

    return Primitive("attenuate-cap", _prim_attenuate)


def install_sandboxed_file_primitives(env: Environment) -> None:
    """Override standard destructive file I/O primitives with capability-enforced versions.

    Calls without an active FileSystemCapability are physically blocked with AccessDeniedException.
    """

    def _require_fs_cap(action: str) -> FileSystemCapability:
        cap = get_active_capability("fs-cap")
        if cap is None or not isinstance(cap, FileSystemCapability):
            raise AccessDeniedException(
                f"FileSystemCapability (fs-cap) required to call '{action}'"
            )
        return cap

    def sandboxed_open_output_file(path: Any) -> Any:
        if not isinstance(path, str):
            raise TypeError(f"open-output-file: expected string, got {path!r}")
        cap = _require_fs_cap("open-output-file")
        return cap.open_output_file(path)

    def sandboxed_open_input_file(path: Any) -> Any:
        if not isinstance(path, str):
            raise TypeError(f"open-input-file: expected string, got {path!r}")
        cap = _require_fs_cap("open-input-file")
        return cap.open_input_file(path)

    def sandboxed_open_binary_output_file(path: Any) -> Any:
        if not isinstance(path, str):
            raise TypeError(f"open-binary-output-file: expected string, got {path!r}")
        cap = _require_fs_cap("open-binary-output-file")
        return cap.open_binary_output_file(path)

    def sandboxed_open_binary_input_file(path: Any) -> Any:
        if not isinstance(path, str):
            raise TypeError(f"open-binary-input-file: expected string, got {path!r}")
        cap = _require_fs_cap("open-binary-input-file")
        return cap.open_binary_input_file(path)

    def sandboxed_call_with_output_file(path: Any, proc: Any) -> Any:
        if not isinstance(path, str):
            raise TypeError(f"call-with-output-file: expected string, got {path!r}")
        cap = _require_fs_cap("call-with-output-file")
        return cap.call_with_output_file(path, proc)

    def sandboxed_call_with_input_file(path: Any, proc: Any) -> Any:
        if not isinstance(path, str):
            raise TypeError(f"call-with-input-file: expected string, got {path!r}")
        cap = _require_fs_cap("call-with-input-file")
        return cap.call_with_input_file(path, proc)

    def sandboxed_file_exists_p(path: Any) -> bool:
        if not isinstance(path, str):
            raise TypeError(f"file-exists?: expected string, got {path!r}")
        cap = _require_fs_cap("file-exists?")
        return cap.file_exists(path)

    def sandboxed_delete_file(path: Any) -> None:
        if not isinstance(path, str):
            raise TypeError(f"delete-file: expected string, got {path!r}")
        cap = _require_fs_cap("delete-file")
        cap.delete_file(path)

    # Bind sandboxed primitives into the environment
    env.define(
        Symbol.intern("open-output-file"),
        Primitive("open-output-file", sandboxed_open_output_file),
    )
    env.define(
        Symbol.intern("open-input-file"),
        Primitive("open-input-file", sandboxed_open_input_file),
    )
    env.define(
        Symbol.intern("open-binary-output-file"),
        Primitive("open-binary-output-file", sandboxed_open_binary_output_file),
    )
    env.define(
        Symbol.intern("open-binary-input-file"),
        Primitive("open-binary-input-file", sandboxed_open_binary_input_file),
    )
    env.define(
        Symbol.intern("call-with-output-file"),
        Primitive("call-with-output-file", sandboxed_call_with_output_file),
    )
    env.define(
        Symbol.intern("call-with-input-file"),
        Primitive("call-with-input-file", sandboxed_call_with_input_file),
    )
    env.define(
        Symbol.intern("file-exists?"),
        Primitive("file-exists?", sandboxed_file_exists_p),
    )
    env.define(
        Symbol.intern("delete-file"), Primitive("delete-file", sandboxed_delete_file)
    )


__all__ = [
    "Capability",
    "CapabilityError",
    "AccessDeniedException",
    "PortQuotaExceededException",
    "FileSystemCapability",
    "NetworkCapability",
    "ManagedPortMixin",
    "ManagedTextualOutputPort",
    "ManagedTextualInputPort",
    "ManagedBinaryOutputPort",
    "ManagedBinaryInputPort",
    "wrap_managed_port",
    "make_loopback_textual_port",
    "make_loopback_binary_port",
    "TaintedValue",
    "TaintLeakViolationException",
    "taint",
    "is_tainted",
    "untaint",
    "check_sink",
    "with_capabilities",
    "get_active_capability",
    "get_active_capabilities",
    "WithCapsTransformer",
    "make_with_caps_primitive",
    "make_fs_cap_primitive",
    "make_net_cap_primitive",
    "make_attenuate_cap_primitive",
    "install_sandboxed_file_primitives",
]

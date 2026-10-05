"""R7RS Module and Library System for ILISP.

Implements define-library, import, and export with support for import set
modifiers (only, except, prefix, rename) and a global LibraryRegistry.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from ilisp.env import Environment, make_initial_env
from ilisp.types import Cons, Symbol, is_null, is_pair, to_py_list


def parse_library_name(name_expr: Any) -> Tuple[str, ...]:
    """Parse a Scheme library name S-expression (e.g. (scheme base)) into a string tuple."""
    if not is_pair(name_expr):
        raise SyntaxError(f"Library name must be a non-empty list, got {name_expr!r}")
    parts: List[str] = []
    curr = name_expr
    while is_pair(curr):
        elem = curr.car
        if isinstance(elem, Symbol):
            parts.append(elem.name)
        elif isinstance(elem, int):
            parts.append(str(elem))
        else:
            raise SyntaxError(f"Invalid library name component: {elem!r}")
        curr = curr.cdr
    if not is_null(curr):
        raise SyntaxError(f"Dotted pair cannot be used in library name: {name_expr!r}")
    return tuple(parts)


class Library:
    """Represents a loaded R7RS library with an isolated environment and export bindings."""

    def __init__(
        self,
        name: Tuple[str, ...],
        exports: Dict[Symbol, Any],
        env: Environment,
    ) -> None:
        self.name: Tuple[str, ...] = name
        self.exports: Dict[Symbol, Any] = exports
        self.env: Environment = env

    def __repr__(self) -> str:
        name_str = " ".join(self.name)
        return f"<Library ({name_str}) with {len(self.exports)} exports>"


class LibraryRegistry:
    """Registry maintaining all loaded and built-in R7RS libraries."""

    def __init__(self) -> None:
        self._libraries: Dict[Tuple[str, ...], Library] = {}
        self._init_builtin_libraries()

    def _init_builtin_libraries(self) -> None:
        """Initialize standard R7RS and ILISP built-in libraries."""
        # 1. Base Environment
        base_env = make_initial_env(preload_stdlib=True)

        # (scheme base)
        base_exports: Dict[Symbol, Any] = {}
        # Export all standard bindings except python and internal ones
        for sym, val in base_env.bindings.items():
            if not sym.name.startswith("py-") and not sym.name.startswith("_"):
                base_exports[sym] = val
        self.register(Library(("scheme", "base"), base_exports, base_env))

        # (scheme write)
        write_exports: Dict[Symbol, Any] = {}
        for name in (
            "display",
            "write",
            "newline",
            "write-char",
            "write-string",
            "flush-output-port",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                write_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "write"), write_exports, base_env))

        # (scheme read)
        read_exports: Dict[Symbol, Any] = {}
        read_sym = Symbol.intern("read")
        if read_sym in base_env.bindings:
            read_exports[read_sym] = base_env.bindings[read_sym]
        self.register(Library(("scheme", "read"), read_exports, base_env))

        # (scheme file)
        file_exports: Dict[Symbol, Any] = {}
        for name in (
            "open-input-file",
            "open-output-file",
            "open-binary-input-file",
            "open-binary-output-file",
            "call-with-port",
            "call-with-input-file",
            "call-with-output-file",
            "with-input-from-file",
            "with-output-to-file",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                file_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "file"), file_exports, base_env))

        # (scheme load)
        load_exports: Dict[Symbol, Any] = {}
        load_sym = Symbol.intern("load")
        if load_sym in base_env.bindings:
            load_exports[load_sym] = base_env.bindings[load_sym]
        self.register(Library(("scheme", "load"), load_exports, base_env))

        # (scheme char)
        char_exports: Dict[Symbol, Any] = {}
        for name in (
            "char-alphabetic?",
            "char-ci<=?",
            "char-ci<?",
            "char-ci=?",
            "char-ci>=?",
            "char-ci>?",
            "char-downcase",
            "char-foldcase",
            "char-lower-case?",
            "char-numeric?",
            "char-upcase",
            "char-upper-case?",
            "char-whitespace?",
            "digit-value",
            "string-ci<=?",
            "string-ci<?",
            "string-ci=?",
            "string-ci>=?",
            "string-ci>?",
            "string-downcase",
            "string-foldcase",
            "string-upcase",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                char_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "char"), char_exports, base_env))

        # (scheme cxr)
        cxr_exports: Dict[Symbol, Any] = {}
        for name in (
            "caaar",
            "caadr",
            "cadar",
            "caddr",
            "cdaar",
            "cdadr",
            "cddar",
            "cdddr",
            "caaaar",
            "caaadr",
            "caadar",
            "caaddr",
            "cadaar",
            "cadadr",
            "caddar",
            "cadddr",
            "cdaaar",
            "cdaadr",
            "cdadar",
            "cdaddr",
            "cddaar",
            "cddadr",
            "cdddar",
            "cddddr",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                cxr_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "cxr"), cxr_exports, base_env))

        # (scheme complex)
        complex_exports: Dict[Symbol, Any] = {}
        for name in (
            "angle",
            "imag-part",
            "magnitude",
            "make-polar",
            "make-rectangular",
            "real-part",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                complex_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "complex"), complex_exports, base_env))

        # (scheme time)
        time_exports: Dict[Symbol, Any] = {}
        for name in (
            "current-second",
            "current-jiffy",
            "jiffies-per-second",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                time_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "time"), time_exports, base_env))

        # (scheme process-context)
        pc_exports: Dict[Symbol, Any] = {}
        for name in (
            "command-line",
            "emergency-exit",
            "exit",
            "get-environment-variable",
            "get-environment-variables",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                pc_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "process-context"), pc_exports, base_env))

        # (scheme inexact)
        inexact_exports: Dict[Symbol, Any] = {}
        for name in (
            "acos",
            "asin",
            "atan",
            "cos",
            "exp",
            "finite?",
            "infinite?",
            "log",
            "nan?",
            "sin",
            "sqrt",
            "tan",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                inexact_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "inexact"), inexact_exports, base_env))

        # (scheme lazy)
        lazy_exports: Dict[Symbol, Any] = {}
        for name in (
            "delay",
            "delay-force",
            "force",
            "make-promise",
            "promise?",
            "__make-promise-from-thunk",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                lazy_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "lazy"), lazy_exports, base_env))

        # (scheme case-lambda)
        case_lambda_exports: Dict[Symbol, Any] = {}
        case_lambda_sym = Symbol.intern("case-lambda")
        if case_lambda_sym in base_env.bindings:
            case_lambda_exports[case_lambda_sym] = base_env.bindings[case_lambda_sym]
        self.register(Library(("scheme", "case-lambda"), case_lambda_exports, base_env))

        # (scheme eval)
        eval_exports: Dict[Symbol, Any] = {}
        for name in ("eval", "environment"):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                eval_exports[sym] = base_env.bindings[sym]
        self.register(Library(("scheme", "eval"), eval_exports, base_env))

        # (scheme repl)
        repl_exports: Dict[Symbol, Any] = {}
        repl_sym = Symbol.intern("interaction-environment")
        if repl_sym in base_env.bindings:
            repl_exports[repl_sym] = base_env.bindings[repl_sym]
        self.register(Library(("scheme", "repl"), repl_exports, base_env))

        # (scheme r5rs)
        r5rs_exports: Dict[Symbol, Any] = dict(base_exports)
        self.register(Library(("scheme", "r5rs"), r5rs_exports, base_env))

        # (ilisp python)
        py_exports: Dict[Symbol, Any] = {}
        for name in (
            "py-import",
            "py-call",
            "py-get",
            "py-set!",
            "sequence-view",
            "py-eval",
            "import-python",
            "->>",
            "|>>",
            ".",
        ):
            sym = Symbol.intern(name)
            if sym in base_env.bindings:
                py_exports[sym] = base_env.bindings[sym]
        self.register(Library(("ilisp", "python"), py_exports, base_env))

    def register(self, lib: Library) -> None:
        """Register a library under its tuple name."""
        self._libraries[lib.name] = lib

    def get(self, name: Tuple[str, ...]) -> Optional[Library]:
        """Lookup a registered library by name tuple."""
        return self._libraries.get(name)

    def has(self, name: Tuple[str, ...]) -> bool:
        """Check if library is registered."""
        return name in self._libraries


# Global registry singleton
GLOBAL_LIBRARY_REGISTRY = LibraryRegistry()


def resolve_import_set(
    import_spec: Any,
    registry: Optional[LibraryRegistry] = None,
) -> Dict[Symbol, Any]:
    """Resolve an R7RS import-set into a dictionary of symbol to value bindings.

    Supports:
    - (lib-name ...)
    - (only import-set id ...)
    - (except import-set id ...)
    - (prefix import-set prefix-id)
    - (rename import-set (orig-id new-id) ...)
    """
    if registry is None:
        registry = GLOBAL_LIBRARY_REGISTRY

    if not is_pair(import_spec):
        raise SyntaxError(f"Malformed import-set: {import_spec!r}")

    head = import_spec.car

    # 1. (only import-set id ...)
    if isinstance(head, Symbol) and head.name == "only":
        args = to_py_list(import_spec.cdr)
        if len(args) < 2:
            raise SyntaxError("only requires import-set and at least one identifier")
        sub_bindings = resolve_import_set(args[0], registry)
        only_ids = {arg.name for arg in args[1:] if isinstance(arg, Symbol)}
        return {sym: val for sym, val in sub_bindings.items() if sym.name in only_ids}

    # 2. (except import-set id ...)
    if isinstance(head, Symbol) and head.name == "except":
        args = to_py_list(import_spec.cdr)
        if len(args) < 2:
            raise SyntaxError("except requires import-set and at least one identifier")
        sub_bindings = resolve_import_set(args[0], registry)
        except_ids = {arg.name for arg in args[1:] if isinstance(arg, Symbol)}
        return {
            sym: val for sym, val in sub_bindings.items() if sym.name not in except_ids
        }

    # 3. (prefix import-set prefix-id)
    if isinstance(head, Symbol) and head.name == "prefix":
        args = to_py_list(import_spec.cdr)
        if len(args) != 2 or not isinstance(args[1], Symbol):
            raise SyntaxError("prefix requires import-set and a prefix identifier")
        sub_bindings = resolve_import_set(args[0], registry)
        pfx = args[1].name
        return {
            Symbol.intern(f"{pfx}{sym.name}"): val for sym, val in sub_bindings.items()
        }

    # 4. (rename import-set (orig new) ...)
    if isinstance(head, Symbol) and head.name == "rename":
        args = to_py_list(import_spec.cdr)
        if len(args) < 2:
            raise SyntaxError("rename requires import-set and rename pairs")
        sub_bindings = resolve_import_set(args[0], registry)
        renamed: Dict[Symbol, Any] = dict(sub_bindings)
        for pair in args[1:]:
            p_list = to_py_list(pair)
            if (
                len(p_list) != 2
                or not isinstance(p_list[0], Symbol)
                or not isinstance(p_list[1], Symbol)
            ):
                raise SyntaxError(f"rename pair must be (orig new), got {pair!r}")
            orig_sym = p_list[0]
            new_sym = p_list[1]
            if orig_sym in renamed:
                val = renamed.pop(orig_sym)
                renamed[new_sym] = val
        return renamed

    # 5. Direct library name: (lib-name ...)
    lib_name = parse_library_name(import_spec)
    lib = registry.get(lib_name)
    if lib is None:
        raise NameError(f"Library not found: ({' '.join(lib_name)})")
    return dict(lib.exports)


def execute_define_library(
    form: Any,
    registry: Optional[LibraryRegistry] = None,
) -> Library:
    """Parse and execute a (define-library (name ...) decl ...) declaration."""
    from ilisp.evaluator import eval_expr

    if registry is None:
        registry = GLOBAL_LIBRARY_REGISTRY

    args = to_py_list(form.cdr if isinstance(form, Cons) else form)
    if not args:
        raise SyntaxError("define-library requires library name and declarations")

    lib_name = parse_library_name(args[0])
    decls = args[1:]

    # Isolated environment for library evaluation
    lib_env = make_initial_env(preload_stdlib=False)
    exports: Dict[Symbol, Any] = {}

    export_decls: List[Any] = []

    # Pass 1: Process imports and begin expressions to populate lib_env
    for decl in decls:
        if not is_pair(decl) or not isinstance(decl.car, Symbol):
            raise SyntaxError(f"Invalid declaration in define-library: {decl!r}")

        decl_type = decl.car.name

        # (import import-set ...)
        if decl_type == "import":
            import_specs = to_py_list(decl.cdr)
            for spec in import_specs:
                bindings = resolve_import_set(spec, registry)
                for sym, val in bindings.items():
                    lib_env.define(sym, val)

        # (begin expr ...)
        elif decl_type == "begin":
            body_exprs = to_py_list(decl.cdr)
            for expr in body_exprs:
                eval_expr(expr, lib_env)

        elif decl_type == "export":
            export_decls.append(decl)
        else:
            raise SyntaxError(f"Unsupported library declaration: {decl_type}")

    # Pass 2: Process exports now that all bindings exist in lib_env
    for decl in export_decls:
        export_specs = to_py_list(decl.cdr)
        for spec in export_specs:
            if isinstance(spec, Symbol):
                # (export id)
                val = lib_env.lookup(spec)
                exports[spec] = val
            elif (
                is_pair(spec)
                and isinstance(spec.car, Symbol)
                and spec.car.name == "rename"
            ):
                # (export (rename orig new) ...)
                r_args = to_py_list(spec.cdr)
                if (
                    len(r_args) != 2
                    or not isinstance(r_args[0], Symbol)
                    or not isinstance(r_args[1], Symbol)
                ):
                    raise SyntaxError(f"Malformed export rename: {spec!r}")
                orig_sym = r_args[0]
                new_sym = r_args[1]
                val = lib_env.lookup(orig_sym)
                exports[new_sym] = val
            else:
                raise SyntaxError(f"Invalid export specifier: {spec!r}")

    library = Library(lib_name, exports, lib_env)
    registry.register(library)
    return library


def execute_import(
    form: Any,
    target_env: Environment,
    registry: Optional[LibraryRegistry] = None,
) -> None:
    """Execute an (import import-set ...) form into the target environment."""
    if registry is None:
        registry = GLOBAL_LIBRARY_REGISTRY

    specs = to_py_list(form.cdr if isinstance(form, Cons) else form)
    for spec in specs:
        bindings = resolve_import_set(spec, registry)
        for sym, val in bindings.items():
            target_env.define(sym, val)

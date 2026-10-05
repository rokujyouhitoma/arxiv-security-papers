"""ILISP Python Interoperability Layer.

This module provides first-class Python-facing APIs for Kernel ILISP,
including immediate evaluation, stateful Evaluator sessions, dynamic module
proxies, and sys.meta_path transparent import hooks for .ilisp and .scm files.
"""

from __future__ import annotations

import importlib.abc
import importlib.machinery
import importlib.util
import os
import sys
import types
from pathlib import Path
from typing import Any, List, Optional, Sequence, Union, cast

from ilisp.env import Environment, make_initial_env
from ilisp.repl import run_file, run_string
from ilisp.types import Cell, SequenceView, Symbol


def _to_scheme_identifier(name: str) -> str:
    """Convert Python snake_case or identifier to Scheme kebab-case."""
    return name.replace("_", "-")


def _to_python_identifier(name: str) -> str:
    """Convert Scheme kebab-case identifier to Python snake_case."""
    return name.replace("-", "_")


def _convert_py_arg_to_lisp(arg: Any) -> Any:
    """Zero-copy adapter converting Python sequences to SequenceView for Scheme consumption."""
    if isinstance(arg, (list, tuple)):
        return SequenceView(arg)
    return arg


class Evaluator:
    """Stateful evaluation session maintaining an ILISP Environment.

    Allows Python applications to evaluate S-expressions, bind and retrieve variables,
    and invoke Scheme procedures with zero-copy argument passing.
    """

    def __init__(
        self,
        env: Optional[Environment] = None,
        preload_stdlib: bool = True,
    ) -> None:
        """Initialize an Evaluator session.

        Args:
            env: Optional existing ILISP Environment. If None, a new global
                 environment is created.
            preload_stdlib: Whether to preload ILISP standard libraries (base, python).
        """
        if env is not None:
            self.env = env
        else:
            self.env = make_initial_env(preload_stdlib=preload_stdlib)

    def eval_string(
        self,
        code: str,
        filename: str = "<eval>",
        backend: str = "interp",
    ) -> Any:
        """Evaluate a sequence of S-expressions from a string and return the last value.

        Args:
            code: Source code string containing one or more S-expressions.
            filename: Source file name for error reporting and source maps.
            backend: Execution backend ('interp' or 'py_ast').
        """
        return run_string(code, env=self.env, filename=filename, backend=backend)

    def eval(self, code: str, backend: str = "interp") -> Any:
        """Alias for eval_string."""
        return self.eval_string(code, backend=backend)

    def get(self, symbol_name: str) -> Any:
        """Retrieve the bound value of a symbol from the environment.

        Supports kebab-case and snake_case fallback lookup:
        1. Exact match (as Symbol.intern(symbol_name))
        2. Kebab-case fallback if name contains '_'
        3. Snake-case fallback if name contains '-'

        Raises:
            NameError: If the symbol is not bound in the environment.
        """
        # 1. Exact match
        sym = Symbol.intern(symbol_name)
        try:
            return self.env.lookup(sym)
        except NameError:
            pass

        # 2. Kebab-case fallback (foo_bar -> foo-bar)
        if "_" in symbol_name:
            kebab = _to_scheme_identifier(symbol_name)
            sym_kebab = Symbol.intern(kebab)
            try:
                return self.env.lookup(sym_kebab)
            except NameError:
                pass

        # 3. Snake-case fallback (foo-bar -> foo_bar)
        if "-" in symbol_name:
            snake = _to_python_identifier(symbol_name)
            sym_snake = Symbol.intern(snake)
            try:
                return self.env.lookup(sym_snake)
            except NameError:
                pass

        raise NameError(f"Symbol '{symbol_name}' not bound in ILISP environment")

    def set(self, symbol_name: str, value: Any) -> None:
        """Define or update a variable binding in the environment.

        If the symbol is already bound, updates it via set! semantics (updating Cell if boxed).
        Otherwise, defines a new binding in the local frame.
        """
        sym = Symbol.intern(symbol_name)
        try:
            self.env.set(sym, value)
        except NameError:
            self.env.define(sym, value)

    def call(self, symbol_name: str, *args: Any) -> Any:
        """Invoke a Scheme procedure bound to symbol_name with Python arguments.

        Python lists and tuples are automatically wrapped into zero-copy SequenceView
        for Scheme list consumption.

        Args:
            symbol_name: Name of the procedure in the environment.
            *args: Arguments to pass to the procedure.

        Returns:
            Result of the procedure call.

        Raises:
            NameError: If the symbol is not found.
            TypeError: If the retrieved value is not callable.
        """
        proc = self.get(symbol_name)
        if not callable(proc):
            raise TypeError(
                f"Symbol '{symbol_name}' is not callable, got {type(proc).__name__}: {proc!r}"
            )
        adapted_args = [_convert_py_arg_to_lisp(a) for a in args]
        return proc(*adapted_args)


class IlispModuleProxy:
    """Dynamic transparent proxy exposing an ILISP Environment as a Python module object."""

    def __init__(
        self,
        env: Environment,
        name: Optional[str] = None,
        filepath: Optional[str] = None,
    ) -> None:
        object.__setattr__(self, "_env", env)
        object.__setattr__(
            self, "_name", name or (Path(filepath).stem if filepath else "ilisp_module")
        )
        object.__setattr__(self, "_filepath", filepath)

    @property
    def env(self) -> Environment:
        """Return the underlying ILISP Environment."""
        return cast(Environment, object.__getattribute__(self, "_env"))

    def _find_symbol_val(self, name: str) -> Any:
        """Lookup symbol in the underlying environment with snake/kebab fallback."""
        env: Environment = object.__getattribute__(self, "_env")
        sym = Symbol.intern(name)
        try:
            val = env.lookup(sym)
            return self._wrap_callable(val)
        except NameError:
            pass

        if "_" in name:
            kebab = _to_scheme_identifier(name)
            sym_kebab = Symbol.intern(kebab)
            try:
                val = env.lookup(sym_kebab)
                return self._wrap_callable(val)
            except NameError:
                pass

        if "-" in name:
            snake = _to_python_identifier(name)
            sym_snake = Symbol.intern(snake)
            try:
                val = env.lookup(sym_snake)
                return self._wrap_callable(val)
            except NameError:
                pass

        raise AttributeError(
            f"Module '{object.__getattribute__(self, '_name')}' has no attribute '{name}'"
        )

    def _wrap_callable(self, val: Any) -> Any:
        """Wrap callable so that Python lists/tuples are automatically converted to SequenceView."""
        if callable(val):

            def wrapper(*args: Any) -> Any:
                adapted_args = [_convert_py_arg_to_lisp(a) for a in args]
                return val(*adapted_args)

            return wrapper
        return val

    def __getattr__(self, name: str) -> Any:
        # Avoid intercepting Python internal dunder methods
        if name.startswith("__") and name.endswith("__"):
            raise AttributeError(name)
        return self._find_symbol_val(name)

    def __getitem__(self, key: str) -> Any:
        try:
            return self._find_symbol_val(key)
        except AttributeError as e:
            raise KeyError(str(e)) from e

    def eval(self, code: str, backend: str = "interp") -> Any:
        """Evaluate an S-expression string inside this module's environment."""
        env: Environment = object.__getattribute__(self, "_env")
        return run_string(code, env=env, backend=backend)

    def __dir__(self) -> List[str]:
        """Collect all bound identifiers for IDE completion and inspection."""
        names = set()
        env: Environment = object.__getattribute__(self, "_env")
        # List module frame symbols first
        for sym in env.bindings.keys():
            names.add(sym.name)
            if "-" in sym.name:
                names.add(_to_python_identifier(sym.name))
        return sorted(names)

    def __repr__(self) -> str:
        name = object.__getattribute__(self, "_name")
        fp = object.__getattribute__(self, "_filepath")
        loc_str = f" from '{fp}'" if fp else ""
        return f"<IlispModuleProxy '{name}'{loc_str}>"


def load_ilisp_module(
    filepath: Union[str, Path],
    env: Optional[Environment] = None,
    name: Optional[str] = None,
    backend: str = "interp",
) -> IlispModuleProxy:
    """Load and execute an ILISP file (.ilisp or .scm) and return an IlispModuleProxy.

    Args:
        filepath: Path to the .ilisp or .scm file.
        env: Optional target Environment. If None, a fresh child environment is created.
        name: Optional module name. Defaults to the file stem.
        backend: Execution backend ('interp' or 'py_ast').

    Returns:
        IlispModuleProxy wrapping the module environment.

    Raises:
        FileNotFoundError: If the file does not exist.
        IsADirectoryError: If the path is a directory.
    """
    path = Path(filepath).resolve()
    if not path.exists():
        raise FileNotFoundError(f"ILISP source file not found: {filepath}")
    if path.is_dir():
        raise IsADirectoryError(
            f"Expected ILISP source file, but got directory: {filepath}"
        )

    if env is None:
        base_env = make_initial_env()
        file_env = Environment(parent=base_env)
    else:
        file_env = env

    run_file(str(path), env=file_env, backend=backend)
    module_name = name or path.stem
    return IlispModuleProxy(env=file_env, name=module_name, filepath=str(path))


# Alias for backward and forward ergonomics
load_module = load_ilisp_module


# --- sys.meta_path Import Hook ---


class IlispImportLoader(importlib.abc.Loader):
    """Import loader that compiles/evaluates .ilisp and .scm source files into Python modules."""

    def __init__(self, filename: str) -> None:
        self.filename = filename

    def create_module(
        self, spec: importlib.machinery.ModuleSpec
    ) -> Optional[types.ModuleType]:
        # Return None to use default module creation
        return None

    def exec_module(self, module: types.ModuleType) -> None:
        module.__file__ = self.filename
        module.__loader__ = self

        base_env = make_initial_env()
        file_env = Environment(parent=base_env)
        run_file(self.filename, env=file_env)

        # Create module proxy
        proxy = IlispModuleProxy(file_env, name=module.__name__, filepath=self.filename)
        module.__env__ = file_env  # type: ignore[attr-defined]
        module.__proxy__ = proxy  # type: ignore[attr-defined]
        module.eval = lambda code, backend="interp": run_string(  # type: ignore[attr-defined]
            code, env=file_env, backend=backend
        )

        # Export file-level bindings into module.__dict__
        for sym, val in file_env.bindings.items():
            real_val = val.get() if isinstance(val, Cell) else val
            # Scheme exact name
            module.__dict__[sym.name] = real_val
            # Python snake_case alias if contains '-'
            if "-" in sym.name:
                py_name = _to_python_identifier(sym.name)
                if py_name not in module.__dict__:
                    module.__dict__[py_name] = real_val


class IlispImportFinder(importlib.abc.MetaPathFinder):
    """MetaPathFinder that resolves .ilisp and .scm files from sys.path."""

    SUPPORTED_EXTENSIONS = (".ilisp", ".scm")

    def find_spec(
        self,
        fullname: str,
        path: Optional[Sequence[str]],
        target: Optional[types.ModuleType] = None,
    ) -> Optional[importlib.machinery.ModuleSpec]:
        # We only support top-level or sub-package modules
        search_paths = list(path) if path is not None else sys.path
        module_name = fullname.rpartition(".")[-1]

        for p in search_paths:
            if not p or not os.path.isdir(p):
                continue
            for ext in self.SUPPORTED_EXTENSIONS:
                candidate = os.path.join(p, module_name + ext)
                if os.path.isfile(candidate):
                    return importlib.machinery.ModuleSpec(
                        fullname,
                        IlispImportLoader(candidate),
                        origin=candidate,
                    )
        return None


_FINDER_INSTANCE: Optional[IlispImportFinder] = None


def register_import_hook() -> bool:
    """Register ILISP sys.meta_path import finder hook.

    Returns:
        True if the hook was registered, False if it was already registered.
    """
    global _FINDER_INSTANCE
    if _FINDER_INSTANCE is not None and _FINDER_INSTANCE in sys.meta_path:
        return False

    if _FINDER_INSTANCE is None:
        _FINDER_INSTANCE = IlispImportFinder()

    sys.meta_path.insert(0, _FINDER_INSTANCE)
    return True


def unregister_import_hook() -> bool:
    """Unregister ILISP sys.meta_path import finder hook.

    Returns:
        True if the hook was unregistered, False if it was not found.
    """
    global _FINDER_INSTANCE
    if _FINDER_INSTANCE is not None and _FINDER_INSTANCE in sys.meta_path:
        sys.meta_path.remove(_FINDER_INSTANCE)
        _FINDER_INSTANCE = None
        return True
    return False

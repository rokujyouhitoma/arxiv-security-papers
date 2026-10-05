"""S-Path Deterministic AST Patch and CAS (Compare-And-Swap) Engine.

Implements DSN-32 Section 6.2 & Section 6.3:
- S-Path deterministic tree traversal without lexical ambiguity.
- CAS (Compare-And-Swap) replacement semantics to prevent LLM hallucination and collision.
"""

from __future__ import annotations

from typing import Any, List, Optional, Sequence, Tuple, Union

from ilisp.reader import read_one
from ilisp.types import (
    NIL,
    Cons,
    Primitive,
    Symbol,
    Vector,
    car,
    cdr,
    is_pair,
    to_lisp_list,
    to_py_list,
)


class SPathError(Exception):
    """Base exception for S-Path traversal and parsing errors."""


class SPathNotFoundError(SPathError):
    """Raised when an S-Path cannot be resolved in the AST."""


class CasMismatchError(Exception):
    """Raised when the expected AST node at an S-Path does not match the actual node (CAS collision)."""

    def __init__(
        self,
        target_path: SPath,
        expected: Any,
        actual: Any,
        message: Optional[str] = None,
    ) -> None:
        self.target_path = target_path
        self.expected = expected
        self.actual = actual
        if message is None:
            message = (
                f"CAS Mismatch at S-Path {target_path}: expected {expected!r}, "
                f"but found actual AST node {actual!r}"
            )
        super().__init__(message)
        self.message = message

    def to_diagnostic(self) -> Cons:
        """Convert into an S-expression diagnostic structure."""
        from alisp.repair.diagnostic import Diagnostic

        diag = Diagnostic(
            severity="error",
            type_name=":cas-mismatch",
            blame=":caller",
            expected=self.expected,
            received=self.actual,
            target_path=self.target_path,
            hint="The expected AST node does not match the current AST. Re-read the target node and verify the S-Path.",
        )
        return diag.to_sexpr()


class SPath:
    """Represents a deterministic AST path for unambiguous node selection."""

    def __init__(self, elements: Sequence[Union[int, str, Symbol]]) -> None:
        # Normalize elements: Symbol -> str name
        norm: List[Union[int, str]] = []
        for el in elements:
            if isinstance(el, Symbol):
                norm.append(el.name)
            elif isinstance(el, (int, str)):
                norm.append(el)
            else:
                norm.append(str(el))
        self.elements: Tuple[Union[int, str], ...] = tuple(norm)

    def __repr__(self) -> str:
        elems_str = " ".join(str(e) for e in self.elements)
        return (
            f"(root {elems_str})"
            if not (self.elements and self.elements[0] == "root")
            else f"({' '.join(str(e) for e in self.elements)})"
        )

    def __str__(self) -> str:
        return self.__repr__()

    def __eq__(self, other: object) -> bool:
        if isinstance(other, SPath):
            return self.elements == other.elements
        return False

    def __hash__(self) -> int:
        return hash(self.elements)

    def to_sexpr(self) -> Cons:
        """Convert SPath to Scheme S-expression list: (root ...) or similar."""
        items: List[Any] = []
        for el in self.elements:
            if isinstance(el, int):
                items.append(el)
            else:
                items.append(Symbol.intern(str(el)))
        return to_lisp_list(items)


def parse_spath(path_input: Any) -> SPath:
    """Parse an S-Path from a Scheme S-expression, Python list/tuple, or string.

    Accepts:
    - (root 2 3 1)
    - (target-path (root 2 3 1))
    - ["root", 2, 3, 1] or [2, 3, 1]
    - "(root 2 3 1)"
    """
    if isinstance(path_input, SPath):
        return path_input

    if isinstance(path_input, str):
        path_input = read_one(path_input)

    # Unwrap (target-path ...) wrapper if present
    if is_pair(path_input):
        first = car(path_input)
        if isinstance(first, Symbol) and first.name == "target-path":
            inner = cdr(path_input)
            if is_pair(inner):
                path_input = car(inner)

    if is_pair(path_input):
        py_list = to_py_list(path_input)
        return SPath(py_list)
    elif isinstance(path_input, (list, tuple)):
        return SPath(path_input)
    else:
        raise SPathError(f"Invalid S-Path specification: {path_input!r}")


def is_ast_equal(a: Any, b: Any) -> bool:
    """Compare two AST nodes for semantic equivalence, ignoring source locations."""
    if a is b:
        return True
    if isinstance(a, Symbol) and isinstance(b, Symbol):
        return a.name == b.name
    if isinstance(a, Cons) and isinstance(b, Cons):
        return is_ast_equal(a.car, b.car) and is_ast_equal(a.cdr, b.cdr)
    if isinstance(a, Vector) and isinstance(b, Vector):
        if len(a.elements) != len(b.elements):
            return False
        return all(is_ast_equal(x, y) for x, y in zip(a.elements, b.elements))
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return False
        return all(is_ast_equal(x, y) for x, y in zip(a, b))
    # Python primitive types (int, float, str, bool, etc.)
    return bool(a == b)


class ASTCursor:
    """Cursor pointing to an AST node and its parent reference for in-place or functional modification."""

    def __init__(
        self,
        node: Any,
        parent: Optional[Any],
        accessor: Optional[Union[str, int]],
        path: SPath,
    ) -> None:
        self.node = node
        self.parent = parent
        self.accessor = accessor  # "car", "cdr", list index, or Vector index
        self.path = path

    def replace(self, new_node: Any) -> None:
        """Replace the pointed node in-place in its parent container."""
        # Preserve location if new_node doesn't have one and original did
        orig_loc = getattr(self.node, "loc", None)
        if orig_loc is not None and getattr(new_node, "loc", None) is None:
            if isinstance(new_node, Cons):
                new_node.loc = orig_loc

        if self.parent is None:
            # Root node cannot be mutated in parent, caller must update root
            self.node = new_node
            return

        if isinstance(self.parent, Cons):
            if self.accessor == "car":
                self.parent.car = new_node
            elif self.accessor == "cdr":
                self.parent.cdr = new_node
            else:
                raise SPathError(f"Invalid Cons accessor: {self.accessor}")
        elif isinstance(self.parent, list):
            assert isinstance(self.accessor, int)
            self.parent[self.accessor] = new_node
        elif isinstance(self.parent, Vector):
            assert isinstance(self.accessor, int)
            self.parent.elements[self.accessor] = new_node
        else:
            raise SPathError(f"Cannot replace in parent of type {type(self.parent)}")
        self.node = new_node


def resolve_spath(ast: Any, spath: Union[SPath, Any]) -> ASTCursor:
    """Traverse AST following S-Path steps and return an ASTCursor at the target location.

    Step semantics:
    - "root": No-op at beginning of path.
    - int index i:
      - If current node is Cons (representing a proper list):
        access the i-th element of the list (0-indexed).
      - If current node is a Python list:
        access list[i].
      - If current node is a Vector:
        access vector.elements[i].
    - str symbol_name:
      - If current node is a list of top-level forms or a list:
        find the definition with the specified symbol name, e.g. (define (foo ...) ...) or (define foo ...).
    """
    path_obj = parse_spath(spath)
    steps = list(path_obj.elements)

    curr = ast
    parent: Optional[Any] = None
    accessor: Optional[Union[str, int]] = None

    if steps and (steps[0] == "root" or steps[0] == Symbol.intern("root")):
        steps.pop(0)

    for step in steps:
        if isinstance(step, int):
            idx = step
            if isinstance(curr, Cons):
                # Traverse proper list to the idx-th element
                # Each element in a Scheme list (e0 e1 e2 ...) is car of (cdr^k list)
                p_curr: Any = curr
                for _ in range(idx):
                    if not isinstance(p_curr, Cons):
                        raise SPathNotFoundError(
                            f"Index {idx} out of range in list at S-Path {path_obj} (stopped at {p_curr!r})"
                        )
                    p_curr = p_curr.cdr

                if not isinstance(p_curr, Cons):
                    raise SPathNotFoundError(
                        f"Index {idx} out of range in list at S-Path {path_obj}"
                    )
                parent = p_curr
                accessor = "car"
                curr = p_curr.car
            elif isinstance(curr, list):
                if idx < 0 or idx >= len(curr):
                    raise SPathNotFoundError(
                        f"Index {idx} out of range in python list of length {len(curr)} at {path_obj}"
                    )
                parent = curr
                accessor = idx
                curr = curr[idx]
            elif isinstance(curr, Vector):
                if idx < 0 or idx >= len(curr.elements):
                    raise SPathNotFoundError(
                        f"Index {idx} out of range in Vector of length {len(curr.elements)} at {path_obj}"
                    )
                parent = curr
                accessor = idx
                curr = curr.elements[idx]
            else:
                raise SPathNotFoundError(
                    f"Cannot index non-collection AST node {curr!r} with index {idx} at {path_obj}"
                )
        elif isinstance(step, (str, Symbol)):
            target_name = step.name if isinstance(step, Symbol) else str(step)
            # Find definition matching symbol name in a list of forms or within a begin/module
            found = False
            if isinstance(curr, list):
                for i, form in enumerate(curr):
                    if _matches_definition(form, target_name):
                        parent = curr
                        accessor = i
                        curr = form
                        found = True
                        break
            elif isinstance(curr, Cons):
                p_curr = curr
                idx = 0
                while isinstance(p_curr, Cons):
                    form = p_curr.car
                    if _matches_definition(form, target_name):
                        parent = p_curr
                        accessor = "car"
                        curr = form
                        found = True
                        break
                    p_curr = p_curr.cdr
                    idx += 1
            if not found:
                raise SPathNotFoundError(
                    f"Definition or symbol '{target_name}' not found at {path_obj}"
                )
        else:
            raise SPathError(f"Unsupported S-Path step: {step!r}")

    return ASTCursor(node=curr, parent=parent, accessor=accessor, path=path_obj)


def _matches_definition(form: Any, name: str) -> bool:
    """Check if form is (define (name ...) ...) or (define name ...) or (define/c (name ...) ...)."""
    if not is_pair(form):
        return False
    head = car(form)
    if isinstance(head, Symbol) and head.name in (
        "define",
        "define/c",
        "define-values",
    ):
        rest = cdr(form)
        if is_pair(rest):
            target = car(rest)
            if isinstance(target, Symbol) and target.name == name:
                return True
            if is_pair(target):
                fn_sym = car(target)
                if isinstance(fn_sym, Symbol) and fn_sym.name == name:
                    return True
    return False


class PatchSpec:
    """Specification of an atomic AST patch with CAS verification."""

    def __init__(
        self,
        target_path: SPath,
        expected_original: Any,
        replace_with: Any,
    ) -> None:
        self.target_path = target_path
        self.expected_original = expected_original
        self.replace_with = replace_with

    @classmethod
    def from_sexpr(cls, form: Any) -> PatchSpec:
        """Parse (patch (target-path ...) (expected-original ...) (replace-with ...))."""
        if not is_pair(form):
            raise SPathError(f"Invalid patch form: {form!r}")
        head = car(form)
        if not (isinstance(head, Symbol) and head.name == "patch"):
            raise SPathError(f"Expected (patch ...), got {head!r}")

        entries = to_py_list(cdr(form))
        target_path: Optional[SPath] = None
        expected_original: Any = None
        replace_with: Any = None
        has_expected = False
        has_replace = False

        for entry in entries:
            if not is_pair(entry):
                continue
            key = car(entry)
            if not isinstance(key, Symbol):
                continue
            val_pair = cdr(entry)
            val = car(val_pair) if is_pair(val_pair) else NIL
            if key.name == "target-path":
                target_path = parse_spath(val)
            elif key.name in ("expected-original", "expected"):
                expected_original = val
                has_expected = True
            elif key.name in ("replace-with", "replacement"):
                replace_with = val
                has_replace = True

        if target_path is None or not has_expected or not has_replace:
            raise SPathError(
                f"Patch specification must contain target-path, expected-original, and replace-with: {form!r}"
            )

        return cls(target_path, expected_original, replace_with)


def apply_patch(
    ast: Any,
    patch_spec: Union[PatchSpec, Any],
) -> Any:
    """Apply an atomic CAS patch to an AST.

    1. Resolves target-path using S-Path deterministic traversal.
    2. Validates that current node equals expected-original (CAS check).
       - If mismatch: raises CasMismatchError.
    3. Replaces target node with replace-with atomically.
    4. Returns updated AST.
    """
    spec = (
        patch_spec
        if isinstance(patch_spec, PatchSpec)
        else PatchSpec.from_sexpr(patch_spec)
    )

    cursor = resolve_spath(ast, spec.target_path)

    # CAS Verification
    if not is_ast_equal(cursor.node, spec.expected_original):
        raise CasMismatchError(
            target_path=spec.target_path,
            expected=spec.expected_original,
            actual=cursor.node,
        )

    # Atomic Replacement
    cursor.replace(spec.replace_with)

    # If root itself was replaced without a parent
    if cursor.parent is None:
        return spec.replace_with

    return ast


def make_patch_primitive() -> Primitive:
    """Scheme primitive for (patch ...)."""

    def _prim_patch(form: Any, *args: Any) -> Any:
        # If passed as (patch (target-path ...) ...)
        if args:
            all_parts = [form] + list(args)
            form = to_lisp_list(all_parts)
        return apply_patch(form, form)

    return Primitive("patch", _prim_patch)

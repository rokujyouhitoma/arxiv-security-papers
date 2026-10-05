"""ALisp Self-Repair Subsystem.

Provides deterministic S-Path AST traversal, CAS (Compare-And-Swap) replacement,
and structured diagnostic generation with macro source location inversion.
"""

from __future__ import annotations

from alisp.repair.diagnostic import (
    Diagnostic,
    MacroExpansionRegistry,
    format_diagnostic,
    invert_source_location,
)
from alisp.repair.patch import (
    ASTCursor,
    CasMismatchError,
    PatchSpec,
    SPath,
    SPathError,
    SPathNotFoundError,
    apply_patch,
    is_ast_equal,
    make_patch_primitive,
    parse_spath,
    resolve_spath,
)

__all__ = [
    "Diagnostic",
    "MacroExpansionRegistry",
    "format_diagnostic",
    "invert_source_location",
    "SPath",
    "SPathError",
    "SPathNotFoundError",
    "CasMismatchError",
    "PatchSpec",
    "apply_patch",
    "is_ast_equal",
    "make_patch_primitive",
    "parse_spath",
    "resolve_spath",
    "ASTCursor",
]

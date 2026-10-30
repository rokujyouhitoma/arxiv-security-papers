#!/usr/bin/env python3
r"""
ULisp S-Expression Parenthesis Depth & Syntax Linter (lint_sexpr.py)
Conforms to Issue #628 and DSN-33 Architecture Specification.

High-performance, zero-dependency linter for Scheme (.scm) source files.
Detects:
  - Unclosed parentheses '(' at EOF with exact line/column of the opening paren.
  - Unexpected extra closing parentheses ')' with exact line/column.
  - Unclosed string literals '"' at EOF.
  - Unclosed block comments '#|' at EOF.
Accurately skips:
  - Line comments (; ... \n)
  - String literals ("...") including escape sequences (\" and \\)
  - Character literals (#\(, #\), #\space, #\newline, #\xNN, etc.)
  - Nested block comments (#| ... |#)
"""

import sys
import os
from typing import List, Tuple, Optional


class LintError:
    def __init__(self, filepath: str, line: int, col: int, message: str, line_text: str = ""):
        self.filepath = filepath
        self.line = line
        self.col = col
        self.message = message
        self.line_text = line_text

    def __str__(self) -> str:
        s = f"{self.filepath}:{self.line}:{self.col}: error: {self.message}"
        if self.line_text:
            s += f"\n    {self.line_text.rstrip()}"
            pointer = " " * (self.col - 1) + "^"
            s += f"\n    {pointer}"
        return s


def lint_scheme_source(filepath: str, content: str) -> List[LintError]:
    errors: List[LintError] = []
    lines = content.splitlines(keepends=True)

    def get_line_text(l_num: int) -> str:
        if 1 <= l_num <= len(lines):
            return lines[l_num - 1]
        return ""

    n = len(content)
    i = 0
    line = 1
    col = 1

    # stack contains tuples of (line, col, char)
    paren_stack: List[Tuple[int, int, str]] = []

    while i < n:
        c = content[i]

        # 1. Newline tracking
        if c == '\n':
            line += 1
            col = 1
            i += 1
            continue

        # 2. Line comment (; ... \n)
        if c == ';':
            while i < n and content[i] != '\n':
                i += 1
                col += 1
            continue

        # 3. String literal ("...")
        if c == '"':
            str_line = line
            str_col = col
            i += 1
            col += 1
            closed = False
            while i < n:
                sc = content[i]
                if sc == '\\':
                    i += 1
                    col += 1
                    if i < n:
                        if content[i] == '\n':
                            line += 1
                            col = 1
                        else:
                            col += 1
                        i += 1
                elif sc == '"':
                    i += 1
                    col += 1
                    closed = True
                    break
                elif sc == '\n':
                    line += 1
                    col = 1
                    i += 1
                else:
                    col += 1
                    i += 1
            if not closed:
                errors.append(
                    LintError(
                        filepath,
                        str_line,
                        str_col,
                        "unclosed string literal starting here",
                        get_line_text(str_line),
                    )
                )
                return errors
            continue

        # 4. Hash-prefixed forms (#\, #|, etc.)
        if c == '#' and i + 1 < n:
            next_c = content[i + 1]

            # 4a. Character literal: #\
            if next_c == '\\':
                # Skip '#' and '\'
                i += 2
                col += 2
                if i < n:
                    char_c = content[i]
                    if char_c in ('(', ')'):
                        # #\( or #\) - single paren character literal
                        i += 1
                        col += 1
                    elif char_c in (' ', '\t', '\r', '\n', ';', '"'):
                        # #\ followed by whitespace/delimiter (e.g. #\ )
                        i += 1
                        col += 1
                    else:
                        # Named character or hex code (e.g. #\newline, #\space, #\alarm, #\x0A)
                        while i < n and content[i] not in (' ', '\t', '\r', '\n', '(', ')', ';', '"'):
                            i += 1
                            col += 1
                continue

            # 4b. Block comment: #| ... |# (with nesting support)
            if next_c == '|':
                blk_line = line
                blk_col = col
                i += 2
                col += 2
                depth = 1
                while i < n and depth > 0:
                    if content[i] == '\n':
                        line += 1
                        col = 1
                        i += 1
                    elif content[i] == '#' and i + 1 < n and content[i + 1] == '|':
                        depth += 1
                        i += 2
                        col += 2
                    elif content[i] == '|' and i + 1 < n and content[i + 1] == '#':
                        depth -= 1
                        i += 2
                        col += 2
                    else:
                        col += 1
                        i += 1
                if depth > 0:
                    errors.append(
                        LintError(
                            filepath,
                            blk_line,
                            blk_col,
                            "unclosed block comment '#|' starting here",
                            get_line_text(blk_line),
                        )
                    )
                    return errors
                continue

        # 5. Parentheses
        if c == '(':
            paren_stack.append((line, col, '('))
            i += 1
            col += 1
            continue

        if c == ')':
            if not paren_stack:
                errors.append(
                    LintError(
                        filepath,
                        line,
                        col,
                        "unexpected closing ')' without matching opening parenthesis",
                        get_line_text(line),
                    )
                )
                return errors
            paren_stack.pop()
            i += 1
            col += 1
            continue

        # Any other character
        col += 1
        i += 1

    # Check for unclosed parens at EOF
    if paren_stack:
        for p_line, p_col, p_char in reversed(paren_stack):
            errors.append(
                LintError(
                    filepath,
                    p_line,
                    p_col,
                    f"unclosed '{p_char}' (depth {len(paren_stack)} remaining at EOF)",
                    get_line_text(p_line),
                )
            )
            # Report the innermost/first problematic unclosed paren prominently
            break

    return errors


def lint_file(filepath: str) -> List[LintError]:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception as e:
        return [LintError(filepath, 1, 1, f"failed to read file: {e}")]
    return lint_scheme_source(filepath, content)


def main() -> int:
    args = sys.argv[1:]
    if not args or "--help" in args or "-h" in args:
        print("Usage: lint_sexpr.py [--quiet] <file1.scm> [file2.scm ...]")
        return 0

    quiet = False
    files: List[str] = []
    for a in args:
        if a == "--quiet" or a == "-q":
            quiet = True
        else:
            files.append(a)

    all_errors: List[LintError] = []
    file_count = 0

    for fpath in files:
        if not os.path.exists(fpath):
            all_errors.append(LintError(fpath, 1, 1, "file not found"))
            continue
        file_count += 1
        errs = lint_file(fpath)
        all_errors.extend(errs)

    if all_errors:
        for err in all_errors:
            print(str(err), file=sys.stderr)
        if not quiet:
            print(f"\n[FAIL] S-expression parenthesis linter detected {len(all_errors)} error(s) across {file_count} file(s).", file=sys.stderr)
        return 1
    else:
        if not quiet:
            print(f"[PASS] S-expression parenthesis check passed for {file_count} file(s) (all balanced).")
        return 0


if __name__ == "__main__":
    sys.exit(main())

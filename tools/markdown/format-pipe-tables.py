#!/usr/bin/env python3
"""Align top-level Markdown pipe tables without changing their cell contents.

Run: format-pipe-tables.py FILE.md > formatted.md
     format-pipe-tables.py --in-place FILE.md
     format-pipe-tables.py --check FILE.md
Input: one UTF-8 Markdown file (use '-' for stdin).
Output: formatted Markdown on stdout, or an updated file with --in-place.
Warnings go to stderr. --check writes nothing and exits 1 if formatting is
needed; errors exit 2. Requires only Python's standard library.

Supports optional outer pipes, escaped pipes, and alignment markers. As in
GitHub-style tables, literal pipes inside code spans must be escaped. Widths
measure Markdown source (including backticks), using Unicode combining and
East Asian width properties; complex emoji may vary by editor. Fenced code
blocks are untouched. Tables nested in lists/quotes or indented code are not
formatted. Ragged tables and cells containing tabs are skipped with warnings.
Cell text is never wrapped or truncated. Original line endings are preserved.
"""

import argparse
from pathlib import Path
import re
import sys
import unicodedata


SEPARATOR = re.compile(r":?-+:?")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")


def split_row(line):
    """Split unescaped pipes; backslashes and inline markup stay verbatim."""
    text = line.rstrip("\r\n")
    # Restrict to unindented tables to avoid list and indented-code contexts.
    if not text or text[0].isspace() or text.startswith(">"):
        return None
    parts = []
    start = 0
    slashes = 0
    for index, char in enumerate(text):
        if char == "|" and slashes % 2 == 0:
            parts.append(text[start:index].strip(" "))
            start = index + 1
        slashes = slashes + 1 if char == "\\" else 0
    if not parts:
        return None
    parts.append(text[start:].strip(" "))
    if parts[0] == "" and text.startswith("|"):
        parts.pop(0)
    if parts[-1] == "" and text.rstrip(" ").endswith("|"):
        parts.pop()
    return parts or None


def source_width(text):
    return sum(
        0 if unicodedata.combining(char) else
        2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
        for char in text
    )


def ending(line):
    return line[len(line.rstrip("\r\n")):]


def format_markdown(text):
    """Return (formatted text, [(one-based line number, warning), ...])."""
    lines = text.splitlines(keepends=True)
    output = []
    warnings = []
    fence = None
    index = 0
    while index < len(lines):
        line = lines[index]
        match = FENCE.match(line.rstrip("\r\n"))
        if fence:
            if (match and match[1][0] == fence[0]
                    and len(match[1]) >= len(fence) and not match[2].strip()):
                fence = None
            output.append(line)
            index += 1
            continue
        if match and not (match[1][0] == "`" and "`" in match[2]):
            fence = match[1]
            output.append(line)
            index += 1
            continue

        header = split_row(line)
        separator = split_row(lines[index + 1]) if index + 1 < len(lines) else None
        if not (header and separator and all(SEPARATOR.fullmatch(c) for c in separator)):
            output.append(line)
            index += 1
            continue

        stop = index + 2
        rows = [header, separator]
        while stop < len(lines):
            if FENCE.match(lines[stop]):
                break
            row = split_row(lines[stop])
            if row is None:
                break
            rows.append(row)
            stop += 1

        problem = None
        if any(len(row) != len(header) for row in rows):
            problem = "inconsistent column counts; table left unchanged"
        elif any("\t" in cell for row in rows for cell in row):
            problem = "tab inside a cell; table left unchanged"
        if problem:
            warnings.append((index + 1, problem))
            output.extend(lines[index:stop])
            index = stop
            continue

        widths = [max(3 + marker.count(":"), *(source_width(row[col])
                  for n, row in enumerate(rows) if n != 1))
                  for col, marker in enumerate(separator)]
        for offset, row in enumerate(rows):
            cells = []
            for cell, marker, width in zip(row, separator, widths):
                left, right = marker.startswith(":"), marker.endswith(":")
                if offset == 1:
                    cells.append((":" if left else "") + "-" * (width - left - right)
                                 + (":" if right else ""))
                else:
                    padding = width - source_width(cell)
                    before = padding // 2 if left and right else padding if right else 0
                    cells.append(" " * before + cell + " " * (padding - before))
            output.append("| " + " | ".join(cells) + " |" + ending(lines[index + offset]))
        index = stop
    return "".join(output), warnings


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", help="UTF-8 Markdown file, or '-' for stdin")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--in-place", action="store_true", help="update the input file")
    mode.add_argument("--check", action="store_true", help="exit 1 if formatting would change the input")
    args = parser.parse_args()
    if args.in_place and args.file == "-":
        parser.error("--in-place requires a file path")
    try:
        original = (sys.stdin.buffer.read() if args.file == "-" else Path(args.file).read_bytes())
        # Preserve a UTF-8 BOM, if present, without hiding a first-line table.
        bom = b"\xef\xbb\xbf" if original.startswith(b"\xef\xbb\xbf") else b""
        formatted, warnings = format_markdown(original[len(bom):].decode("utf-8"))
        result = bom + formatted.encode("utf-8")
        for line, warning in warnings:
            print(f"{args.file}:{line}: warning: {warning}", file=sys.stderr)
        if args.check:
            return int(result != original)
        if args.in_place:
            if result != original:
                Path(args.file).write_bytes(result)
        else:
            sys.stdout.buffer.write(result)
    except (OSError, UnicodeError) as error:
        print(f"{args.file}: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

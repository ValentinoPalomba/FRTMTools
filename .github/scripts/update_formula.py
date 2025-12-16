#!/usr/bin/env python3
"""Update the Homebrew formula fields for URL, SHA, and version."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "Usage: update_formula.py <formula_path> <download_url> <version> <sha>",
            file=sys.stderr,
        )
        return 1

    formula_path = Path(sys.argv[1])
    download_url = sys.argv[2]
    version = sys.argv[3]
    sha = sys.argv[4]

    text = formula_path.read_text()
    replacements = [
        (r'(url\s+")([^"]+)(")', f'\\1{download_url}\\3'),
        (r'(sha256\s+")([^"]+)(")', f'\\1{sha}\\3'),
        (r'(version\s+")([^"]+)(")', f'\\1{version}\\3'),
    ]

    for pattern, replacement in replacements:
        new_text, count = re.subn(pattern, replacement, text, count=1)
        if count == 0:
            print(f"Failed to update pattern: {pattern}", file=sys.stderr)
            return 1
        text = new_text

    formula_path.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

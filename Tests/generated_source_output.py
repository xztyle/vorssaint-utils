#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint and Aster contributors

"""Write generated fixtures and emit the exact compiler input manifest.

Only files emitted during this invocation belong to the test executable.
Unrelated stale files or File Provider conflict copies are not source inputs.
"""
from pathlib import Path


class GeneratedSourceOutput:
    def __init__(self, directory: Path):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True)

    def write(self, name: str, text: str):
        if not name.endswith(".swift") or Path(name).name != name:
            raise ValueError(f"Invalid generated source name: {name!r}")
        path = self.directory / name
        if not path.exists() or path.read_text() != text:
            path.write_text(text)
        print(path)

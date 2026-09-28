#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Aster contributors
set -euo pipefail
cd "$(dirname "$0")/.."
identity="Aster Local Signing"
probe_dir="$(mktemp -d)"
trap 'rm -rf "$probe_dir"' EXIT
swiftc Sources/Vorssaint/Core/AppCodeIdentity.swift Tests/AppIdentity/main.swift -o "$probe_dir/verifier"
cp "$probe_dir/verifier" "$probe_dir/adhoc-verifier"
codesign --force --sign "$identity" --identifier io.github.xztyle.Aster "$probe_dir/verifier"
for name in valid wrong-id adhoc damaged; do
    cp "$probe_dir/adhoc-verifier" "$probe_dir/$name"
done
codesign --force --sign "$identity" --identifier io.github.xztyle.Aster.battery-care "$probe_dir/valid"
codesign --force --sign "$identity" --identifier io.github.xztyle.Other "$probe_dir/wrong-id"
codesign --force --sign - --identifier io.github.xztyle.Aster.battery-care "$probe_dir/adhoc"
cp "$probe_dir/valid" "$probe_dir/damaged"
python3 - "$probe_dir/damaged" <<'PY'
import sys
with open(sys.argv[1], 'r+b') as file:
    file.seek(4096)
    original=file.read(1)
    file.seek(4096)
    file.write(bytes([original[0] ^ 1]))
PY
"$probe_dir/verifier" io.github.xztyle.Aster.battery-care "$probe_dir/valid" accept
for name in wrong-id adhoc damaged; do
    "$probe_dir/verifier" io.github.xztyle.Aster.battery-care "$probe_dir/$name" reject
done
"$probe_dir/adhoc-verifier" io.github.xztyle.Aster.battery-care "$probe_dir/valid" reject
"$probe_dir/verifier" 'invalid" or always' "$probe_dir/valid" reject

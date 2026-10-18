#!/usr/bin/env python3
"""Replace app contents while preserving macOS's registered bundle directory."""

import os
import filecmp
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def verify(bundle):
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)


def code_identity(path):
    result = subprocess.run(['/usr/bin/codesign', '-d', '-r-', '--verbose=4', str(path)],
                            capture_output=True, text=True)
    cdhash = re.search(r'^CDHash=(\w+)$', result.stderr, re.MULTILINE)
    requirement = re.search(r'^designated => (.+)$', result.stdout + result.stderr, re.MULTILINE)
    if result.returncode or not cdhash or not requirement:
        return None
    return cdhash.group(1), requirement.group(1)


def helper_is_registered(name):
    result = subprocess.run(['/bin/launchctl', 'print', 'system/' + name], capture_output=True, text=True)
    if result.returncode == 0:
        return True
    if 'Could not find service' in result.stderr:
        return False
    raise RuntimeError('Cannot check helper registration: ' + name)


def preserve_unchanged_helpers(candidate, destination):
    signature_changed = False
    helpers = Path('Contents/Library/LaunchServices')
    if not (candidate / helpers).is_dir():
        return False
    for replacement in (candidate / helpers).iterdir():
        current = destination / helpers / replacement.name
        if not replacement.is_file() or not current.is_file() or current.is_symlink():
            continue
        identity = code_identity(current)
        if identity is None or identity != code_identity(replacement):
            if helper_is_registered(current.name):
                raise RuntimeError('Stop and unregister the changed helper before updating: ' + current.name)
            continue
        # Retain the live executable's vnode so authenticated XPC remains valid.
        signature_changed |= not filecmp.cmp(current, replacement, shallow=False)
        replacement.unlink()
        os.link(current, replacement)
    return signature_changed


def resign_host(candidate, identity):
    original = code_identity(candidate)
    if not identity or original is None:
        raise RuntimeError('A stable signing identity is required to preserve the running helper')
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity,
                    '--preserve-metadata=identifier,requirements,entitlements,flags',
                    '--timestamp=none', str(candidate)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R=' + original[1], str(candidate)], check=True)


def stage(source, destination, transaction, signing_identity=None):
    candidate = transaction / destination.name
    subprocess.run(['/usr/bin/ditto', '--noextattr', '--noqtn', str(source), str(candidate)], check=True)
    subprocess.run(['/usr/bin/xattr', '-cr', str(candidate)], check=True)
    if preserve_unchanged_helpers(candidate, destination):
        resign_host(candidate, signing_identity)
    verify(candidate)
    return candidate


def replace_existing(candidate, destination, transaction):
    contents = destination / 'Contents'
    previous = transaction / 'PreviousContents'
    os.replace(contents, previous)
    try:
        os.replace(candidate / 'Contents', contents)
        verify(destination)
    except BaseException:
        if contents.exists():
            os.replace(contents, transaction / 'RejectedContents')
        os.replace(previous, contents)
        raise


def install(source, destination, signing_identity=None):
    source, destination = Path(source), Path(destination)
    if not (source / 'Contents').is_dir() or destination.is_symlink():
        raise ValueError('Expected a source app and a regular destination directory')
    if destination.exists() and not (destination / 'Contents').is_dir():
        raise ValueError('Existing destination is not an app bundle')
    transaction = Path(tempfile.mkdtemp(prefix='.aster-install-', dir=destination.parent))
    succeeded = False
    try:
        candidate = stage(source, destination, transaction, signing_identity)
        if destination.exists():
            replace_existing(candidate, destination, transaction)
        else:
            os.replace(candidate, destination)
        succeeded = True
    finally:
        # Preserve the previous contents if even rollback could not finish.
        if succeeded or not (transaction / 'PreviousContents').exists():
            shutil.rmtree(transaction)
    return destination


if __name__ == '__main__':
    install(*sys.argv[1:])

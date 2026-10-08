#!/usr/bin/env python3
"""Create universal macOS DMG and ZIP packages without changing app signatures."""

import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MACHO_MAGICS = {bytes.fromhex(value) for value in (
    'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
    'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca',
)}


def run(*arguments: str) -> str:
    return subprocess.check_output(arguments, text=True).strip()


def validate_app(app: Path) -> str:
    with (app / 'Contents/Info.plist').open('rb') as stream:
        metadata = plistlib.load(stream)
    version = metadata['CFBundleShortVersionString']
    build = metadata['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', build):
        raise ValueError('Application version must use MAJOR.MINOR.PATCH and a numeric build.')
    executable = app / 'Contents/MacOS' / metadata['CFBundleExecutable']
    if not executable.is_file():
        raise ValueError('Application executable is missing.')
    binaries = 0
    for path in app.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic not in MACHO_MAGICS:
            continue
        architectures = set(run('/usr/bin/lipo', '-archs', str(path)).split())
        if not {'x86_64', 'arm64'}.issubset(architectures):
            raise ValueError(f'Universal binary required: {path}: {sorted(architectures)}')
        binaries += 1
    if not binaries:
        raise ValueError('No Mach-O binaries found.')
    print(f'Validated {binaries} universal Mach-O binaries.')
    return f'{version}.{build}'


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('dist'))
    arguments = parser.parse_args()
    if sys.platform != 'darwin':
        parser.error('macOS packaging requires macOS with Xcode command line tools.')
    app = arguments.app.resolve()
    version = validate_app(app)
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    stem = f'llmqueta-{version}-macos-universal'
    targets = [output / f'{stem}{suffix}' for suffix in ('.dmg', '.zip', '.sha256')]
    for target in targets:
        if target.exists():
            raise FileExistsError(f'Refusing to overwrite {target}')
    with tempfile.TemporaryDirectory(prefix='llmqueta-macos-') as directory:
        temporary = Path(directory)
        staging = temporary / 'stage'
        staging.mkdir()
        run('/usr/bin/ditto', str(app), str(staging / app.name))
        shutil.copy2(ROOT / 'LICENSE', staging / 'LICENSE')
        (staging / 'Applications').symlink_to('/Applications')
        disk = temporary / targets[0].name
        archive = temporary / targets[1].name
        run('/usr/bin/hdiutil', 'create', '-volname', 'llmqueta', '-srcfolder',
            str(staging), '-format', 'UDZO', '-ov', str(disk))
        run('/usr/bin/hdiutil', 'verify', str(disk))
        run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', str(staging), str(archive))
        checksums = []
        for source, target in zip((disk, archive), targets):
            with source.open('rb') as stream:
                checksum = hashlib.sha256()
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    checksum.update(block)
                digest = checksum.hexdigest()
            checksums.append(f'{digest}  {target.name}\n')
            # Exclusive creation protects an artifact produced by another invocation.
            with target.open('xb') as stream, source.open('rb') as source_stream:
                shutil.copyfileobj(source_stream, stream)
            print(target)
        with targets[2].open('x') as stream:
            stream.writelines(checksums)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'Packaging failed: {error}')

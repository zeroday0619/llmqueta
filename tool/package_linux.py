#!/usr/bin/env python3
"""Package an existing Flutter Linux release bundle using native packaging tools."""

import argparse
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ARCHITECTURES = {"x86_64": (62, "amd64"), "aarch64": (183, "arm64")}


def version_from_pubspec():
    match = re.search(r"^version:\s*([^\s#]+)", (ROOT / "pubspec.yaml").read_text(), re.M)
    if not match:
        raise ValueError("pubspec.yaml has no version")
    return normalize_version(match.group(1))


def normalize_version(value):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?", value):
        raise ValueError("version must be MAJOR.MINOR.PATCH with an optional numeric +BUILD")
    return value.replace("+", ".")


def validate_bundle(bundle, architecture):
    for relative in ("llmqueta", "lib/libflutter_linux_gtk.so", "lib/libapp.so", "data/icudtl.dat", "data/flutter_assets"):
        if not (bundle / relative).exists():
            raise ValueError(f"missing Flutter release bundle entry: {relative}")
    for entry in bundle.rglob("*"):
        if entry.is_symlink() and not entry.resolve().is_relative_to(bundle.resolve()):
            raise ValueError(f"bundle symlink escapes its directory: {entry}")
        if entry.is_file():
            with entry.open("rb") as stream:
                header = stream.read(20)
            if header[:4] == b"\x7fELF":
                if len(header) < 20 or header[4:6] != b"\x02\x01" or struct.unpack("<H", header[18:20])[0] != ARCHITECTURES[architecture][0]:
                    raise ValueError(f"ELF architecture mismatch: {entry}")
            elif entry in (bundle / "llmqueta", bundle / "lib/libapp.so", bundle / "lib/libflutter_linux_gtk.so"):
                raise ValueError(f"bundle binary must be a 64-bit Linux ELF binary: {entry}")
    if not os.access(bundle / "llmqueta", os.X_OK):
        raise ValueError("bundle executable is not executable")


def stage_payload(bundle, destination):
    application = destination / "usr/lib/llmqueta"
    application.parent.mkdir(parents=True)
    shutil.copytree(bundle, application, symlinks=True)
    for source, relative in (
        (ROOT / "packaging/linux/llmqueta", "usr/bin/llmqueta"),
        (ROOT / "packaging/linux/llmqueta.desktop", "usr/share/applications/llmqueta.desktop"),
        (ROOT / "packaging/assets/llmqueta.png", "usr/share/icons/hicolor/512x512/apps/llmqueta.png"),
        (ROOT / "LICENSE", "usr/share/licenses/llmqueta/LICENSE"),
    ):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755 if relative == "usr/bin/llmqueta" else 0o644)


def run(arguments, **kwargs):
    subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def required_tool(value):
    result = shutil.which(value)
    if not result:
        raise ValueError(f"required executable not found: {value}")
    return str(Path(result).resolve())


def build_package(arguments, work):
    payload = work / "payload"
    stage_payload(arguments.bundle, payload)
    version = arguments.version
    architecture = arguments.architecture
    if arguments.format == "deb":
        control = payload / "DEBIAN/control"
        control.parent.mkdir()
        control.write_text(
            f"Package: llmqueta\nVersion: {version}\nArchitecture: {ARCHITECTURES[architecture][1]}\n"
            "Maintainer: LLM Queta contributors\nSection: utils\nPriority: optional\n"
            "Depends: libgtk-3-0, libstdc++6, libc6\n"
            "Description: Desktop overlay for AI subscription quotas and reset times\n"
        )
        copyright_file = payload / "usr/share/doc/llmqueta/copyright"
        copyright_file.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / "LICENSE", copyright_file)
        artifact = work / f"llmqueta_{version}_{ARCHITECTURES[architecture][1]}.deb"
        run([required_tool("dpkg-deb"), "--root-owner-group", "--build", payload, artifact])
    elif arguments.format == "rpm":
        for directory in ("BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"):
            (work / directory).mkdir()
        with tarfile.open(work / "SOURCES/payload.tar.gz", "w:gz") as archive:
            archive.add(payload / "usr", arcname="usr")
        spec = work / "SPECS/llmqueta.spec"
        spec.write_text(
            f"Name: llmqueta\nVersion: {version}\nRelease: 1\nSummary: AI subscription quota overlay\n"
            "License: Unlicense\nURL: https://github.com/zeroday0619/llmqueta\nSource0: payload.tar.gz\n"
            "Requires: gtk3, libstdc++, glibc\n%global debug_package %{nil}\n"
            "%global __strip /bin/true\n%global __brp_strip /bin/true\n"
            "%description\nDesktop overlay for AI subscription quotas and reset times.\n"
            "%prep\n%setup -q -c\n%build\n%install\nmkdir -p %{buildroot}\ncp -a usr %{buildroot}/\n"
            "%files\n/usr/bin/llmqueta\n/usr/lib/llmqueta\n/usr/share/applications/llmqueta.desktop\n"
            "/usr/share/icons/hicolor/512x512/apps/llmqueta.png\n%license /usr/share/licenses/llmqueta/LICENSE\n"
        )
        run([required_tool("rpmbuild"), "-bb", "--target", architecture, "--define", f"_topdir {work}", spec])
        artifact, = (work / "RPMS").rglob("*.rpm")
    elif arguments.format == "arch":
        if os.geteuid() == 0:
            raise ValueError("makepkg must run as a non-root user")
        with tarfile.open(work / "payload.tar.gz", "w:gz") as archive:
            archive.add(payload / "usr", arcname="usr")
        import hashlib
        digest = hashlib.sha256((work / "payload.tar.gz").read_bytes()).hexdigest()
        (work / "PKGBUILD").write_text(
            f"pkgname=llmqueta\npkgver={version}\npkgrel=1\npkgdesc='AI subscription quota overlay'\n"
            f"arch=('{architecture}')\nurl='https://github.com/zeroday0619/llmqueta'\nlicense=('Unlicense')\n"
            "depends=('gtk3' 'gcc-libs' 'glibc')\noptions=('!strip' '!debug')\nsource=('payload.tar.gz')\n"
            f"sha256sums=('{digest}')\npackage() {{\n  cp -a \"$srcdir/usr\" \"$pkgdir/\"\n}}\n"
        )
        configuration = work / "makepkg.conf"
        configuration.write_text(f'source /etc/makepkg.conf\nCARCH={architecture}\n')
        run([required_tool("makepkg"), "--config", configuration, "--nodeps", "--noconfirm", "--ignorearch"], cwd=work,
            env={**os.environ, "PKGDEST": str(work), "CARCH": architecture})
        artifacts = list(work.glob("*.pkg.tar.*"))
        artifact, = [path for path in artifacts if not path.name.endswith(".sig")]
    else:
        if not arguments.runtime_file or not arguments.runtime_file.is_file():
            raise ValueError("--runtime-file must identify a pinned AppImage runtime")
        linuxdeploy = required_tool(arguments.linuxdeploy or "linuxdeploy")
        appimagetool = required_tool(arguments.appimagetool or "appimagetool")
        plugin = Path(required_tool(arguments.gtk_plugin or "linuxdeploy-plugin-gtk.sh"))
        if plugin.name != "linuxdeploy-plugin-gtk.sh":
            raise ValueError("GTK plugin must be named linuxdeploy-plugin-gtk.sh")
        # linuxdeploy uses NO_STRIP to preserve the prebuilt Flutter binaries.
        # https://github.com/linuxdeploy/linuxdeploy/issues/72
        environment = {**os.environ, "ARCH": architecture, "DEPLOY_GTK_VERSION": "3", "NO_STRIP": "1",
                       "PATH": f"{plugin.parent}{os.pathsep}{os.environ.get('PATH', '')}"}
        launcher = payload / "usr/bin/llmqueta"
        # linuxdeploy must install an ELF executable before patching its dependencies.
        launcher.unlink()
        command = [linuxdeploy, "--appdir", payload, "--executable", payload / "usr/lib/llmqueta/llmqueta",
                   "--desktop-file", payload / "usr/share/applications/llmqueta.desktop",
                   "--icon-file", payload / "usr/share/icons/hicolor/512x512/apps/llmqueta.png", "--plugin", "gtk"]
        for library in sorted((payload / "usr/lib/llmqueta/lib").glob("*.so*")):
            command.extend(["--library", library])
        run(command, env=environment)
        # Flutter locates assets relative to its executable, so retain the bundle layout.
        launcher.unlink(missing_ok=True)
        shutil.copyfile(ROOT / "packaging/linux/llmqueta", launcher)
        launcher.chmod(0o755)
        artifact = work / f"llmqueta-{version}-{architecture}.AppImage"
        run([appimagetool, "--runtime-file", arguments.runtime_file.resolve(), payload, artifact], env=environment)
    if not artifact.is_file() or artifact.stat().st_size == 0:
        raise ValueError("packaging tool did not create a nonempty artifact")
    destination = arguments.output / artifact.name
    # Exclusive creation protects existing artifacts from accidental replacement.
    with artifact.open("rb") as source, destination.open("xb") as target:
        shutil.copyfileobj(source, target)
    shutil.copymode(artifact, destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", required=True, choices=("deb", "rpm", "arch", "appimage"))
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("dist"))
    parser.add_argument("--architecture", required=True, choices=ARCHITECTURES)
    parser.add_argument("--version")
    parser.add_argument("--linuxdeploy")
    parser.add_argument("--appimagetool")
    parser.add_argument("--gtk-plugin")
    parser.add_argument("--runtime-file", type=Path)
    arguments = parser.parse_args()
    try:
        arguments.version = normalize_version(arguments.version) if arguments.version else version_from_pubspec()
        arguments.bundle = arguments.bundle.resolve()
        arguments.output = arguments.output.resolve()
        validate_bundle(arguments.bundle, arguments.architecture)
        arguments.output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="llmqueta-package-") as directory:
            print(build_package(arguments, Path(directory)))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    main()

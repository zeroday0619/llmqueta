"""Validate packaging contracts with synthetic bundles, without native package builds."""

import argparse
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("package_linux", Path(__file__).resolve().parents[1] / "tool/package_linux.py")
packaging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packaging)


class LinuxPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.bundle = Path(self.temporary.name) / "bundle"
        (self.bundle / "lib").mkdir(parents=True)
        (self.bundle / "data/flutter_assets").mkdir(parents=True)
        (self.bundle / "data/icudtl.dat").write_bytes(b"fixture")
        self.write_elf("llmqueta", 62)
        self.write_elf("lib/libflutter_linux_gtk.so", 62)
        self.write_elf("lib/libapp.so", 62)

    def write_elf(self, relative, machine):
        header = bytearray(64)
        header[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", header, 18, machine)
        path = self.bundle / relative
        path.write_bytes(header)
        path.chmod(0o755)

    def test_valid_x86_bundle(self):
        packaging.validate_bundle(self.bundle, "x86_64")

    def test_valid_arm_bundle(self):
        for entry in ("llmqueta", "lib/libapp.so", "lib/libflutter_linux_gtk.so"):
            self.write_elf(entry, 183)
        packaging.validate_bundle(self.bundle, "aarch64")

    def test_mixed_architecture_rejected(self):
        self.write_elf("lib/libapp.so", 183)
        with self.assertRaisesRegex(ValueError, "architecture mismatch"):
            packaging.validate_bundle(self.bundle, "x86_64")

    def test_missing_assets_rejected(self):
        (self.bundle / "data/icudtl.dat").unlink()
        with self.assertRaisesRegex(ValueError, "missing Flutter"):
            packaging.validate_bundle(self.bundle, "x86_64")

    def test_external_symlink_rejected(self):
        (self.bundle / "external").symlink_to(Path(self.temporary.name))
        with self.assertRaisesRegex(ValueError, "symlink escapes"):
            packaging.validate_bundle(self.bundle, "x86_64")

    def test_version_injection_rejected(self):
        for version in ("1.0.0\nRequires: evil", "$(id)", "1.0.0;id", "../1.0.0"):
            with self.assertRaises(ValueError):
                packaging.normalize_version(version)
        self.assertEqual(packaging.normalize_version("0.1.0+1"), "0.1.0.1")

    def test_stage_retains_bundle_and_helper(self):
        self.write_elf("claude_statusline", 62)
        destination = Path(self.temporary.name) / "stage"
        packaging.stage_payload(self.bundle, destination)
        self.assertTrue((destination / "usr/lib/llmqueta/claude_statusline").exists())
        self.assertTrue((destination / "usr/lib/llmqueta/data/flutter_assets").is_dir())
        self.assertTrue((destination / "usr/bin/llmqueta").stat().st_mode & 0o111)
        self.assertTrue((destination / "usr/share/applications/llmqueta.desktop").exists())


    def test_non_elf_library_rejected(self):
        (self.bundle / "lib/libapp.so").write_text("placeholder")
        with self.assertRaisesRegex(ValueError, "must be a 64-bit Linux ELF"):
            packaging.validate_bundle(self.bundle, "x86_64")

    def test_debian_metadata_and_existing_artifact_protection(self):
        output = Path(self.temporary.name) / "output"
        output.mkdir()
        arguments = SimpleNamespace(bundle=self.bundle, version="0.1.0.1",
                                    architecture="aarch64", format="deb", output=output)
        observed = []

        def fake_dpkg(command, **options):
            control = (Path(command[-2]) / "DEBIAN/control").read_text()
            observed.append(control)
            Path(command[-1]).write_bytes(b"synthetic package fixture")

        with patch.object(packaging, "required_tool", return_value="dpkg-deb"), patch.object(packaging, "run", side_effect=fake_dpkg):
            first = Path(self.temporary.name) / "first"
            first.mkdir()
            artifact = packaging.build_package(arguments, first)
            self.assertIn("Architecture: arm64", observed[0])
            self.assertIn("Depends: libgtk-3-0, libstdc++6, libc6", observed[0])
            artifact.write_bytes(b"existing artifact")
            second = Path(self.temporary.name) / "second"
            second.mkdir()
            with self.assertRaises(FileExistsError):
                packaging.build_package(arguments, second)
            self.assertEqual(artifact.read_bytes(), b"existing artifact")

    def test_arch_target_overrides_build_host(self):
        output = Path(self.temporary.name) / "output"
        output.mkdir()
        arguments = SimpleNamespace(bundle=self.bundle, version="0.1.0.1",
                                    architecture="aarch64", format="arch", output=output)
        work = Path(self.temporary.name) / "arch"
        work.mkdir()

        def fake_makepkg(command, **options):
            self.assertIn("--ignorearch", command)
            self.assertIn("CARCH=aarch64", (work / "makepkg.conf").read_text())
            self.assertIn("arch=('aarch64')", (work / "PKGBUILD").read_text())
            (work / "llmqueta-0.1.0.1-1-aarch64.pkg.tar.zst").write_bytes(b"synthetic archive")

        with patch.object(packaging.os, "geteuid", return_value=1000), patch.object(packaging, "required_tool", return_value="makepkg"), patch.object(packaging, "run", side_effect=fake_makepkg):
            artifact = packaging.build_package(arguments, work)
        self.assertEqual(artifact.name, "llmqueta-0.1.0.1-1-aarch64.pkg.tar.zst")


    def test_appimage_deploys_elf_before_restoring_launcher(self):
        output = Path(self.temporary.name) / "output"
        output.mkdir()
        work = Path(self.temporary.name) / "appimage"
        work.mkdir()
        runtime = work / "runtime"
        runtime.write_bytes(b"synthetic runtime")
        arguments = SimpleNamespace(bundle=self.bundle, version="0.1.0.1", architecture="x86_64",
                                    format="appimage", output=output, runtime_file=runtime,
                                    linuxdeploy="linuxdeploy", appimagetool="appimagetool",
                                    gtk_plugin="linuxdeploy-plugin-gtk.sh")
        calls = []

        def fake_tool(command, **options):
            calls.append(command[0])
            launcher = work / "payload/usr/bin/llmqueta"
            if command[0] == "linuxdeploy":
                self.assertFalse(launcher.exists())
                # Reject unsupported switches instead of accepting arbitrary mocked commands.
                parser = argparse.ArgumentParser(allow_abbrev=False)
                for option in ("--appdir", "--executable", "--desktop-file", "--icon-file", "--plugin"):
                    parser.add_argument(option, required=True)
                parser.add_argument("--library", action="append", default=[])
                deployed = parser.parse_args([str(value) for value in command[1:]])
                self.assertEqual(options["env"]["NO_STRIP"], "1")
                self.assertEqual(options["env"]["DEPLOY_GTK_VERSION"], "3")
                self.assertEqual(deployed.plugin, "gtk")
                self.assertEqual({Path(value).name for value in deployed.library},
                                 {"libapp.so", "libflutter_linux_gtk.so"})
                executable = Path(deployed.executable)
                self.assertEqual(executable.read_bytes()[:4], b"\x7fELF")
                launcher.write_bytes(executable.read_bytes())
            else:
                self.assertTrue(launcher.read_text().startswith("#!/bin/sh"))
                self.assertIn('"$APPDIR/usr/lib/llmqueta"', launcher.read_text())
                self.assertIn("--runtime-file", command)
                Path(command[-1]).write_bytes(b"synthetic AppImage")

        with patch.object(packaging, "required_tool", side_effect=lambda value: value), patch.object(packaging, "run", side_effect=fake_tool):
            artifact = packaging.build_package(arguments, work)
        self.assertEqual(calls, ["linuxdeploy", "appimagetool"])
        self.assertEqual(artifact.name, "llmqueta-0.1.0.1-x86_64.AppImage")


if __name__ == "__main__":
    unittest.main()

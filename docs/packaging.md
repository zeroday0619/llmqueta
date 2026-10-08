# Desktop packaging

The `Desktop validation` workflow runs on pushes, pull requests and manual dispatch. After all macOS, Windows and Linux validation jobs succeed, it calls the reusable `Desktop packages` workflow to build packages and upload workflow artifacts with SHA-256 manifests. Tag pushes follow the same validation path without a second packaging run. A new run cancels an older run for the same branch, tag or pull request.

The `Desktop packages` workflow can also run manually for packaging alone. This direct entry point runs packaging contract tests but does not run the desktop analysis and Flutter test matrix. Neither workflow publishes GitHub Releases. Download the packages from the completed run's **Artifacts** section in the repository's **Actions** tab.

| Platform | Package | Architecture |
| --- | --- | --- |
| macOS | `.dmg`, `.zip` | Universal: x86_64 and arm64 |
| Debian | `.deb` | amd64, arm64 |
| Fedora | `.rpm` | x86_64, aarch64 |
| Arch Linux | `.pkg.tar.zst` | x86_64 |
| Arch Linux ARM | `.pkg.tar.zst` | aarch64 |
| Linux | `.AppImage` | x86_64, aarch64 |

RISC-V is excluded because Flutter's supported desktop targets are x64 and Arm64. A RISC-V package would require a separately maintained engine and toolchain. See [Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms).

Package versions replace the numeric build separator with a dot: `0.1.0+1` becomes `0.1.0.1`. The scripts reject other version forms and protect existing output files. Use a fresh output directory for a rebuild.

## macOS

Use Flutter 3.47.6, Xcode and Python 3.10 or newer on macOS:

```sh
flutter pub get
flutter build macos --release
python3 tool/package_macos.py \
  --app build/macos/Build/Products/Release/llmqueta.app \
  --output dist
```

The script checks every Mach-O file for both x86_64 and arm64, copies the application without modifying its signatures, adds the Unlicense text and an Applications shortcut, then creates and verifies a compressed DMG. It also creates a ZIP and a checksum manifest. Drag the application into Applications to install it.

The workflow does not configure Developer ID signing or Apple notarization. These packages must not be described as notarized releases. Distribution requiring Gatekeeper approval needs a separate signing and notarization setup.

## Linux

Build on the target architecture with Flutter 3.47.6 and Python 3.10 or newer. CI uses Ubuntu 22.04 native x86_64 and aarch64 runners. Install Flutter's Linux build prerequisites and the packaging tools needed for the selected format.

```sh
flutter pub get
flutter build linux --release
python3 tool/package_linux.py --format deb \
  --bundle build/linux/x64/release/bundle --architecture x86_64 --output dist
```

For aarch64 use `--architecture aarch64` and `build/linux/arm64/release/bundle`. The packager checks the ELF architecture of the executable and bundled libraries before staging them. It preserves the Flutter `lib` and `data` directories under `/usr/lib/llmqueta`; the desktop entry launches `/usr/bin/llmqueta`.

| Format | Required packaging tools | Installation |
| --- | --- | --- |
| `deb` | `dpkg-deb` | `sudo apt install ./dist/*.deb` |
| `rpm` | `rpmbuild` | `sudo dnf install ./dist/*.rpm` |
| `arch` | `makepkg`, `zstd`; run as a non-root user | `sudo pacman -U ./dist/*.pkg.tar.zst` |
| `appimage` | linuxdeploy, GTK plugin, appimagetool, AppImage runtime | `chmod +x ./dist/*.AppImage` then run the file |

Pass `--format rpm` or `--format arch` to the same command. Arch packaging repacks a prebuilt native bundle and sets `CARCH` explicitly; it does not cross-compile Flutter. The aarch64 package targets Arch Linux ARM, which is separate from Arch Linux.

AppImage tooling is downloaded from fixed upstream versions with checked SHA-256 digests:

```sh
python3 .github/scripts/fetch_appimage_tools.py \
  --architecture x86_64 --output /tmp/llmqueta-appimage-tools
APPIMAGE_EXTRACT_AND_RUN=1 python3 tool/package_linux.py \
  --format appimage --architecture x86_64 \
  --bundle build/linux/x64/release/bundle --output dist \
  --linuxdeploy /tmp/llmqueta-appimage-tools/linuxdeploy.AppImage \
  --appimagetool /tmp/llmqueta-appimage-tools/appimagetool.AppImage \
  --gtk-plugin /tmp/llmqueta-appimage-tools/linuxdeploy-plugin-gtk.sh \
  --runtime-file /tmp/llmqueta-appimage-tools/runtime
```

The packaging script itself does not download tools. GTK is deployed through the GTK plugin. AppImage still depends on a compatible host kernel and glibc; packaging on Ubuntu 22.04 does not promise compatibility with older distributions.

The optional `claude_statusline` executable is included when it exists in the supplied Linux bundle. The workflow does not build this helper; the Dart source setup described in the README remains available.

## Validation

```sh
python3 -m unittest discover -s test -p 'packaging_*_test.py'
git diff --check
```

Fixture tests check staging, architecture rejection, version validation, metadata and overwrite protection. They do not execute Flutter binaries.

CI installs the Debian and Fedora packages in distribution containers and checks shared-library resolution. It performs the same check for Arch x86_64 and checks AppImage extraction. Arch Linux ARM has no installation or runtime check. Container checks do not establish GUI behavior, compositor compatibility or provider connectivity; those require a desktop session on each target.

# Validation record

Validated on macOS arm64 with Flutter 3.47.6, Dart 3.13.5, and Xcode 27.2 on 2026-10-08.

## Initial desktop validation

| Check | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test tool integration_test` | Passed. |
| `flutter analyze` | Passed with no issues. |
| `flutter test` | 41 tests passed, including connected-only filtering, empty/loading states, stale observations, platform-specific close controls, HUD mode switching, Escape restoration, and persistence callbacks. |
| `flutter test integration_test/desktop_test.dart -d macos` | Passed. The native window rendered demo providers and applied pinning, opacity, and compact sizing. The macOS title bar reported a separate positive height and the Flutter close button was absent. |
| HUD native controls | Passed within the desktop integration test: HUD forces pinning, caps opacity at 0.90, uses width 320, and restores normal pinning, opacity, and size. |
| `flutter test integration_test/hud_startup_test.dart -d macos` | Passed. `--hud` startup renders the HUD with reachable return and close controls. |
| `flutter build macos --debug` | Passed. |
| `flutter build macos --release` | Passed. The executable contains arm64 and x86_64 slices; runtime tests were on arm64 only. |
| Compiled Claude statusline bridge | Valid input, quota-only persistence, and invalid-input handling passed using an isolated temporary home directory. |
| Preview renderer | Connected-only, empty, demo, and HUD states passed. The corresponding `build/overlay-*-preview.png` images were visually inspected. These images show Flutter content without native window chrome or desktop compositing. |

The Flutter launcher reported a failure to foreground the integration-test app. Its native tests still completed successfully. The separate desktop UI automation connection failed to start, so an operating-system screenshot was not captured. The preview image is a Flutter-rendered demo, not proof of account connectivity.

Provider tests cover fixture parsing, missing data, stale observations, authenticated loopback HTTP, fallback, redirect rejection, a continuously streaming response deadline, and a spawned mock Codex process handshake and cleanup. No live-account quota accuracy claim follows from those tests. Claude Code requires the documented statusline configuration before it supplies live data.

`dart run tool/check_providers.dart` also ran against the current local environment. Codex returned a live observation with one quota window and one reset timestamp. Claude was unavailable because its bridge snapshot was absent. Antigravity was unavailable because no eligible running local server was discovered. The diagnostic prints connection status and field counts, not credentials or percentage values. The Codex result was not independently compared with the provider UI.

Windows and Linux runners and a three-platform GitHub Actions workflow are included. Their native builds and runtime behavior have not been executed in this macOS workspace. Linux compositor behavior, Windows discovery, live-provider compatibility, release signing, and notarization remain outside the completed local validation.


## Token and credit display validation

The token and credit extension was validated on the same macOS environment on 2026-10-08.

| Check | Result |
| --- | --- |
| `flutter test` | 78 tests passed, including token and credit parsing, missing daily buckets, Claude transcript deduplication, cache accounting, optional RPC failures and timeouts, token-only providers, stale-data preservation, and narrow-window scrolling. |
| `flutter analyze` | Passed with no issues. |
| Dart formatting and `git diff --check` | Passed. |
| `flutter build macos --release` | Passed. |
| Compiled Claude statusline bridge | Quota and session metadata persistence, ignored-field filtering, session identifier length limits, and invalid-input handling passed under an isolated temporary home directory. |
| `flutter test tool/render_preview_test.dart` | Four preview cases passed. Normal and HUD previews were visually inspected with sample token counts, a credit balance, and reset credits. |
| Live Codex CLI 0.160.1 | The integrated source returned account lifetime tokens, a credit balance, and reset credits. No bucket for the current date or selected-session total was returned; those values remained unavailable. No account identifiers or credentials were recorded in this document. |

Codex session totals were verified with mock responses for an explicitly configured thread ID. Claude totals were verified against synthetic local transcript fixtures, including nested and duplicate records; they represent retained local history rather than an account-wide total. Antigravity token counts and spendable credit balances are unavailable through the current adapter.

The native window-control integration tests above were not rerun for this extension. Windows and Linux native behavior remains unverified locally. The generated preview images use sample data and do not establish provider accuracy.

# LLM Queta

A Flutter desktop overlay for Codex, Claude, and Antigravity subscription quotas. It displays remaining percentages, reset countdowns, observation age, and connection status. Sample values appear only in the explicitly selected demo mode.

## Build and run

Developed with Flutter 3.47.6 and Dart 3.13.5. Install the Flutter stable SDK and the native desktop toolchain for the target operating system.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Use `-d windows` or `-d linux` on those operating systems. Create a release with `flutter build macos`, `flutter build windows`, or `flutter build linux` on the matching host. Launch the executable with `--demo` to preview sample data without provider access. The settings menu can also toggle demo mode.

Run the native window integration test with `flutter test integration_test/desktop_test.dart -d macos`, replacing the device on Windows or Linux. The test uses demo data and checks pinning, opacity, and window size. `.github/workflows/desktop.yml` defines unit tests and release builds for all three operating systems; adding the workflow does not mean those hosted jobs have run.

The macOS build disables App Sandbox because it launches the installed Codex CLI, discovers the user's Antigravity process, and reads the shared Claude snapshot. It is intended for direct desktop distribution, not the Mac App Store sandbox. Release signing and notarization require the distributor's Apple credentials and are not configured here.

## Data connections

Run `dart run tool/check_providers.dart` to check local integration status without printing credentials or quota percentages. The command queries all three providers.

| Provider | Data source | Requirements |
| --- | --- | --- |
| Codex | Official `codex app-server` `account/rateLimits/read` RPC | Installed Codex CLI signed in with a ChatGPT account. Set `LLMQUETA_CODEX_EXECUTABLE` if the executable is outside the app's PATH. |
| Claude | Claude Code `statusLine` JSON | Configure the included bridge. Claude Code reports limits after a response on eligible subscriptions. |
| Antigravity | Local Language Server quota RPC | A running Antigravity instance. This internal protocol can change independently of this app. |

Queta never treats missing quota as zero usage. A reset countdown reaching zero does not restore the displayed allowance: the display waits for a new provider observation. Observations older than ten minutes are marked stale. Provider failures retain previous measurements with a stale indicator when available.

### Codex executable

Codex executable discovery checks PATH and common user install locations. On Windows, use native `codex.exe`; `.cmd`, `.bat`, and `.ps1` shell wrappers are not executed. Set `LLMQUETA_CODEX_EXECUTABLE` to the native binary when needed. An explicit override is authoritative and does not fall back to a different installation.

### Claude statusline bridge

Compile the standalone bridge with the Dart SDK included in Flutter:

```sh
mkdir -p build
dart compile exe tool/claude_statusline.dart -o build/claude_statusline
```

On Windows PowerShell, create the output directory with `New-Item -ItemType Directory -Force build` and use an output path ending in `.exe`. Add the following `statusLine` property to the existing Claude Code settings object, using the absolute executable path on the local machine:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/llmqueta/build/claude_statusline\""
  }
}
```

Merge this property into existing settings rather than replacing the file. If another statusline command is already configured, integrate both commands with a wrapper that supplies the same stdin JSON to each. Queta does not modify Claude settings automatically.

The bridge stores only the supported quota windows and observation timestamp. It does not store conversation content, workspace paths, or credentials. It prints a short Claude quota status so it can also serve as the terminal statusline.

| Platform | Snapshot |
| --- | --- |
| macOS | `~/Library/Application Support/llmqueta/claude.json` |
| Windows | `%APPDATA%/llmqueta/claude.json` |
| Linux | `$XDG_CONFIG_HOME/llmqueta/claude.json`, or `~/.config/llmqueta/claude.json` |

### Antigravity endpoint override

Queta first looks for the running Antigravity Language Server and its process-owned listening ports. On macOS and Linux it uses `ps` and `lsof`; an advertised extension-server port is a fallback when listener discovery is unavailable. On Windows it uses PowerShell process and TCP connection queries. Discovery reads the matching process's CSRF flag in memory and does not save it.

For an explicitly configured local server, set `LLMQUETA_ANTIGRAVITY_URL` to its HTTP(S) origin, such as `https://127.0.0.1:42100`, and `LLMQUETA_ANTIGRAVITY_CSRF_TOKEN` to the token of that same running Language Server process. Ports and tokens can change when Antigravity restarts. Do not commit token values or paste them into issue reports.

Only literal loopback addresses with an explicit port are accepted. Redirects are disabled. Self-signed certificates are accepted only for that configured loopback endpoint. Queta requests `RetrieveUserQuotaSummary` and falls back to `GetUserStatus` for older servers. If a response has no reset timestamp, the app displays that the time is unavailable.

## Interface

- Select **HUD mode** in the settings menu for a small, undecorated panel. HUD always stays on top and caps opacity at 90%; it preserves the normal window's settings for restoration. Drag its header to move it. Use the expand button or press Escape while the HUD has focus to return to the normal window. The close button remains accessible.
- The HUD choice is saved when changed through the UI. Launch with `--hud` to start in HUD mode without changing the saved choice. For example: `open build/macos/Build/Products/Release/llmqueta.app --args --hud` after closing an existing instance.
- Only providers with reported quota windows appear. Unavailable providers stay hidden; an empty state links to setup when no provider is connected. Previously connected providers retain their last observation with a stale indicator during transient errors.
- macOS uses its native title bar and traffic-light controls in a separate area above the Flutter content. Other desktop platforms use the in-app close button.
- Window height adapts to the visible quota windows, with scrolling for longer lists.
- Drag the title area to move the overlay.
- Pin or unpin it using the pin button.
- Use settings for compact view, opacity, demo data, and connection help.
- Refresh manually with the refresh button or Ctrl/Cmd+R. Automatic refresh runs every 60 seconds.
- Hover over a reset countdown to see the local reset timestamp.

Window behavior on Linux depends on the window manager and compositor. In particular, Wayland may restrict window positioning and always-on-top requests. Windows and Linux require builds and runtime verification on their respective operating systems.

## Sources

- [Codex App Server protocol](https://learn.chatgpt.com/docs/app-server)
- [Claude Code statusline data](https://code.claude.com/docs/en/statusline)
- [Antigravity quota UI](https://www.antigravity.google/docs/cli/commands/usage/)
- [CodexBar Antigravity protocol implementation](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift)

The Antigravity adapter uses an internal protocol described by an independent open-source implementation. It is not an official Google integration. Parser fixtures and local transport tests do not establish real-account quota accuracy.

## AI-Generated Code Notice

Parts of this project were created with assistance from AI tools (e.g. large language models). All AI-assisted contributions were reviewed and adapted by maintainers before inclusion. If you need provenance for specific changes, please refer to the Git history and commit messages.